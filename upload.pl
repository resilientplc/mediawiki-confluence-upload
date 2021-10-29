#!/usr/bin/env perl -w
#
# Script to process a set of page files that have been exported from MediaWiki via UWC, and
# converted to Confluence markup (by the UWC, accepting that it does an incomplete conversion).
# Finishes a few items of conversion, uploads the fully converted page to the given space, and
# attaches any files referenced in the page to it.
#
# A configuration file, configuration.properties, is required in the directory where you run this
# script. Please see the sample.configuration.properties for an example.
#
# This script and documentation is provided under the Apache License 2.0 - see LICENSE.txt
#
# To run:
# perl upload.pl 'Page Name One' 'Page Name Two' ... 'Page Name N'
#
# These page names (as Confluence markup files) are expected to exist in the export_directory that
# is configured in the configuration.properties file. Any attachments declared in these pages must
# exist in the attachment_directory that's configured.
#
# Before converting/uploading, you can verify that the attachments declared in the pages are present
# by using the --attachments option. This won't do any conversion/upload.
#
use warnings;
use strict;
use Data::Dumper;
use File::Basename;
use File::Find::Rule;
use File::Spec;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON;
use Text::CSV;

use lib '.';
use TweakMarkup qw(tweak_markup find_attachment_filenames);

# forward declarations
sub load_properties;
sub index_attachments;
sub check_attachments;
sub count_attachments;
sub upload;
sub load_page;
sub create_post_request;
sub create_attachment_post_request;


my $config_file = 'configuration.properties';
my $config = load_properties($config_file);
die "No 'user_name=xxxxx' in $config_file\n" unless defined($config->{user_name});
die "No 'api_token=xxxxx' in $config_file\n" unless defined($config->{api_token});
die "No 'space_key=xxxxx' in $config_file\n" unless defined($config->{space_key});
die "No 'confluence_host_name=xxxxx (like mycompany.atlassian.net)' in $config_file\n" unless defined($config->{confluence_host_name});
die "No 'attachment_directory=xxxxx (like /tmp/attachments)' in $config_file\n" unless defined($config->{attachment_directory});
die "No 'export_directory=xxxxx (like /tmp/uwc/output)' in $config_file\n" unless defined($config->{export_directory});

my $att_dir_len = length($config->{attachment_directory});
my $exp_dir_len = length($config->{export_directory});

# Get the list of pages from the command line...

my @page_paths = (); # array of array references - each array reference is a [page name, file path]
my $errors = 0;
my $attachment_check = 0; # just scan files for attachments, verify their existence
my $count_attachments = 0; # just report whether there are attachments or not
foreach (@ARGV) {
  # process any command line args
  if (/--attachments|-a/) {
    $attachment_check = 1;
  } elsif (/--countattachments|-c/) {
    $count_attachments = 1;
  } elsif (/--allpages|-p/) {
    # scan for all pages in the export directory, rather than specifying pages
    my @pages = glob("$config->{export_directory}/*");
    foreach my $page_path (@pages) {
      my $page_name = substr($page_path, $exp_dir_len + 1);
      push @page_paths, [$page_name, $page_path];
    }

  } elsif (/--help|-h|-\?/) {
    print "./upload.pl [options] 'Page 1 Name' 'Page 2 Name' ... 'Page N Name'\n";
    print "options: --help: show this help\n";
    print "         --attachments: verify existence of the pages' attachment files\n";
    print "         --countattachments: count how many attachments pages have (csv output)\n";
    exit(0);
  } else {
    # Arguments that aren't options (don't start with hyphen) are page names whose files should be
    # found in the export_directory.
    my $page_name = $_;
    my $page_path = File::Spec->catfile($config->{export_directory}, $page_name);
    if (-f $page_path) {
      push @page_paths, [$page_name, $page_path];
    } else {
      warn "Cannot find the page '$page_name' under the export directory '$config->{export_directory}' (path is $page_path)\n";
      $errors = 1;
    }
  }
}

die "Please fix the above problems before continuing\n" if $errors > 0;

my %attachment_lookup = index_attachments();

my $csv = $count_attachments == 1 ? Text::CSV->new ({ binary => 1, auto_diag => 1 }) : undef;

foreach my $page_name_and_path (@page_paths) {
  my ($page_name, $page_path) = (@$page_name_and_path);

  if ($count_attachments == 1) {
    count_attachments($page_name, $page_path);
  } elsif ($attachment_check == 1) {
    check_attachments($page_name, $page_path);
  } else {
    upload($page_name, $page_path);
  }
}

exit(0);

sub index_attachments {
  my $rule = File::Find::Rule->new;
  my @files = $rule->in($config->{attachment_directory});
  my %lookup = ();
  foreach (@files) {
    next if -d $_;
    my $sub_path = substr($_, $att_dir_len);
    my $file_name = basename($sub_path);
    my $attachment_spaces = $file_name;
    $attachment_spaces =~ s/_/ /g;
    $lookup{$attachment_spaces} = $sub_path;
    if ($attachment_spaces ne $file_name) {
      if (exists ($lookup{$file_name})) {
        print "Attachment (space/underscore) collision with $file_name\n";
        print "with spaces($attachment_spaces): $lookup{$attachment_spaces}\n";
        print "original($file_name): $lookup{$file_name}\n\n";
      } else {
        $lookup{$file_name} = $sub_path;
      }
    }
  }
  return %lookup;
}

sub check_attachments {
  my ($page_name, $page_path) = @_;
  print "Checking attachments for '$page_name'...\n";
  my $mostly_confluence_markup = load_page($page_path);
  my @attachments = find_attachment_filenames($mostly_confluence_markup);
  print "Page '$page_name' has " . scalar(@attachments) . " attachment(s):\n";
  my $notfounds = 0;
  foreach my $attachment (@attachments) {
    if (exists $attachment_lookup{$attachment}) {
      my $attachment_sub_path = $attachment_lookup{$attachment};
      my $attachment_path = File::Spec->catfile($config->{attachment_directory}, $attachment_sub_path);
      if (-f $attachment_path) {
        print "++ OK! ++";
      } else {
        print "NOT FOUND";
        $notfounds++;
      }
    } else {
      print "NOT INDEX";
      $notfounds++;
    }
    print "  - '$attachment'\n";
  }
  if ($notfounds > 0) {
    print "$notfounds attachment(s) could not be found in $config->{attachment_directory}\n";
  }
}

sub count_attachments {
  my ($page_name, $page_path) = @_;
  my $mostly_confluence_markup = load_page($page_path);
  my @attachments = find_attachment_filenames($mostly_confluence_markup);
  my $row = [scalar(@attachments), "'$page_name'"];
  my $fh = *STDOUT;
  $csv->say($fh, $row);
}

sub upload {
  my ($page_name, $page_path) = @_;
  print "Checking attachment(s) existence for '$page_name'...\n";
  my $mostly_confluence_markup = load_page($page_path);
  my @attachments = find_attachment_filenames($mostly_confluence_markup);
  my $attachment_errors = 0;
  foreach my $attachment (@attachments) {
    if (exists $attachment_lookup{$attachment}) {
      my $attachment_sub_path = $attachment_lookup{$attachment};
      my $attachment_path = File::Spec->catfile($config->{attachment_directory}, $attachment_sub_path);
      if (! -f $attachment_path) {
        print "  Attachment '$attachment' does not exist in the attachment directory\n";
        $attachment_errors++;
      }
    } else {
      print "  Attachment '$attachment' has no lookup entry\n";
      $attachment_errors++;
    }
  }
  if ($attachment_errors > 0) {
    print "Cannot proceed with missing attachments\n";
    return;
  }

  print "Converting '$page_name' to storage format...\n";

  my $lwp = LWP::UserAgent->new;
  my $base_uri = "https://$config->{confluence_host_name}/wiki/rest/api";

  my $better_confluence_markup = tweak_markup($mostly_confluence_markup);

  my $convert_uri = "$base_uri/contentbody/convert/storage";
  my $convert_json_hash = {
      'representation' => 'wiki',
      'value'          => $better_confluence_markup,
  };
  my $convert_json = encode_json $convert_json_hash;
  # print "convert request is \n$convert_json\n";
  my $convert_req = create_post_request($convert_uri, $convert_json, $config->{user_name}, $config->{'api_token'});
  my $convert_response = $lwp->request( $convert_req );
  unless ($convert_response->is_success) {
    warn "Could not convert markup to storage format\n";
    die "" . Dumper($convert_response) . "\n";
  }
  # print Dumper($convert_response) . "\n";

  print "Uploading storage format version of '$page_name' to Confluence...\n";

  my $storage_format = $convert_response->content();
  my $storage_format_hash = decode_json $storage_format;
  my $storage_value = $storage_format_hash->{value};

  # print Dumper($storage_value) . "\n";

  my $content_uri = "$base_uri/content/";
  my $content_json_hash = {
      'type' => 'page',
      'title' => $page_name,
      'space' => {
          'key' => $config->{space_key},
      },
      'body' => {
          'storage' => {
              'representation' => 'storage',
              'value' => $storage_value,
          },
      },
  };
  my $content_json = encode_json $content_json_hash;
  my $content_req = create_post_request($content_uri, $content_json, $config->{user_name}, $config->{'api_token'});
  my $content_response = $lwp->request( $content_req );
  unless ($content_response->is_success) {
    warn "Could not upload markup to Confluence\n";
    die "" . Dumper($content_response) . "\n";
  }

  # print "content response: " . Dumper($content_response) . "\n";
  my $content_response_json = decode_json $content_response->content();
  my $id = $content_response_json->{id};

  my $attach_uri = "$base_uri/content/$id/child/attachment";

  print "Page '$page_name' (id $id) has " . scalar(@attachments) . " attachment(s):\n";
  foreach my $attachment (@attachments) {
    print "Uploading attachment '$attachment'\n";
    my $attachment_sub_path = $attachment_lookup{$attachment};
    my $attachment_path = File::Spec->catfile($config->{attachment_directory}, $attachment_sub_path);

    my $attach_req = create_attachment_post_request($attach_uri, $attachment_path, $config->{user_name}, $config->{'api_token'});

    my $attach_response = $lwp->request( $attach_req );
    unless ($attach_response->is_success) {
      warn "Could not upload attachment '$attachment' to Confluence\n";
      die "" . Dumper($attach_response) . "\n";
    }
  }
  print "\n";
}

sub create_attachment_post_request {
  my ($uri, $attachment_path, $user_name, $api_token) = @_;
  my $req = HTTP::Request->new(POST => $uri,
    HTTP::Headers->new(
        'Accept'            => 'application/json',
        'X-Atlassian-Token' => 'no-check',
        'Content_Type'      => 'form-data',
        'Content'           => [ $attachment_path ]
    ),
  );
  $req->authorization_basic($user_name, $api_token);
  return $req;
}

sub create_post_request {
  my ($uri, $content, $user_name, $api_token) = @_;
  my $req = HTTP::Request->new('POST', $uri);
  $req->header('Content-Type' => 'application/json');
  $req->authorization_basic($user_name, $api_token);
  $req->content( $content );
  return $req;
}

sub load_page {
  my $path = shift;
  open (my $fh, '<', $path) or die "Can't open $path: $!\n";
  my $data; 
  local $/ = undef;
  $data = <$fh>;
  close $fh;
  return $data;
}

sub load_properties {
  my $config_file_name = shift;
  my $config_hash = {};
  open (my $cfh, '<', $config_file_name) or die "Can't open $config_file_name: $!\n";
  while (<$cfh>) {
    chomp;
    s/^\s*#.*//g;
    next if length($_) == 0;
    my ($k, $v) = split('=', $_);
    $config_hash->{$k} = $v;
  }
  close $cfh;
  return $config_hash;
}
__END__

convert json format:
{
    "representation": "storage",
    "value": "<ac:structured-macro ac:name=\"cheese\" />"
}


upload json format:
{
    "body": {
        "storage": {
            "representation": "storage",
            "value": "<p>This is <br/> a new page</p>"
        }
    },
    "space": {
        "key": "TST"
    },
    "title": "new page",
    "type": "page"
}

