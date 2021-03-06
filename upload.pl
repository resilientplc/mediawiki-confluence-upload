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
sub capture;

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
my $show_features = 0; # just report: Page Name, Has Attachments, Has Tables
my $show_graph = 0; # just show the graph of pages linked to from the requested pages
my $debug = 0;
foreach my $arg (@ARGV) {
  print "arg [$arg]\n" if $debug;
  # process any command line args
  if ($arg =~ /^(--debug|-d)$/) {
    $debug = 1;
  } elsif ($arg =~ /^(--attachments|-a)$/) {
    $attachment_check = 1;
  } elsif ($arg =~ /^(--countattachments|-c)$/) {
    $count_attachments = 1;
  } elsif ($arg =~ /^(--features|-f)$/) {
    $show_features = 1;
    print "Showing features\n" if $debug;
  } elsif ($arg =~ /^(--graph|-g)$/) {
    $show_graph = 1;
    print "Showing link graph\n" if $debug;
  } elsif ($arg =~ /^(--allpages|-p)$/) {
    print "Scanning\n" if $debug;
    # scan for all pages in the export directory, rather than specifying pages
    print "Scanning all pages under $config->{export_directory}\n";
    my @pages = glob("$config->{export_directory}/*");
    foreach my $page_path (@pages) {
      my $page_name = substr($page_path, $exp_dir_len + 1);
      push @page_paths, [$page_name, $page_path];
    }

  } elsif ($arg =~ /^(--help|-h|-\?)$/) {
    print "./upload.pl [options] 'Page 1 Name' 'Page 2 Name' ... 'Page N Name'\n";
    print "options: --help: show this help\n";
    print "         --allpages: scan all pages in the export directory, not just those specified\n";
    print "         --pagesfile=input.txt : process the pages whose names are contained in input.txt\n";
    print "The list of pages provided will be uploaded, with progress written to 'progress.csv'\n\n";
    print "The following options do not upload, but perform tests...\n";
    print "         --attachments: verify existence of the pages' attachment files\n";
    print "         --countattachments: count how many attachments pages have (csv output)\n";
    print "         --features: show page names, attachment state, table state (csv output)\n";
    print "         --graph: show the graph of pages linked to by the set of requested pages\n";
    exit(0);
  } elsif ($arg =~ /--pagesfile=(\S+)/) {
    my $pagesfile = $1;
    open (my $fh, '<', $pagesfile) or die "Can't open $pagesfile: $!\n";
    while (<$fh>) {
      chomp;
      my $page_name = $_;
      my $page_path = File::Spec->catfile($config->{export_directory}, $page_name);
      if (-f $page_path) {
        push @page_paths, [$page_name, $page_path];
      } else {
        warn "Cannot find the page '$page_name' under the export directory '$config->{export_directory}' (path is $page_path)\n";
        $errors = 1;
      }
    }
    close $fh;
  } else {
    # Arguments that aren't options (don't start with hyphen) are page names whose files should be
    # found in the export_directory.
    print "Specified page $arg\n" if $debug;
    my $page_name = $arg;
    my $page_path = File::Spec->catfile($config->{export_directory}, $page_name);
    if (-f $page_path) {
      push @page_paths, [$page_name, $page_path];
    } else {
      warn "Cannot find the page '$page_name' under the export directory '$config->{export_directory}' (path is $page_path)\n";
      $errors = 1;
    }
  }
}

print "Finished argument processing\n" if $debug;

die "Please fix the above problems before continuing\n" if $errors > 0;

print "Indexing attachments...\n";
my %attachment_lookup = index_attachments();
print "... indexed.\n";

print "CSV output?\n" if $debug;
my $csv = $count_attachments == 1 || $show_features == 1 ? Text::CSV->new ({ binary => 1, auto_diag => 1 }) : undef;

my $doing_upload = $count_attachments == 0 && $attachment_check == 0 && $show_features == 0;
my $upload_status = {};

my %page_graph_set = (); # key: page name, value: 1 (irrelevant). It's a set.

foreach my $page_name_and_path (@page_paths) {
  my ($page_name, $page_path) = (@$page_name_and_path);

  if ($count_attachments == 1) {
    count_attachments($page_name, $page_path);
  } elsif ($attachment_check == 1) {
    check_attachments($page_name, $page_path);
  } elsif ($show_features == 1) {
    show_features($page_name, $page_path);
  } elsif ($show_graph == 1) {
    show_graph($page_name);
  } else {
    $upload_status->{$page_name} = upload($page_name, $page_path);
  }
}

if ($show_graph == 1) {
  foreach (sort (keys %page_graph_set)) {
    print "$_\n";
  }
}

if ($doing_upload) {
  my $progress_file = 'progress.csv';
  open (my $fh, '>>', "progress.csv") or die "Can't open $progress_file: $!\n";
  my $csv_progress = Text::CSV->new({ binary => 1, auto_diag => 1 });
  foreach my $page (sort(keys(%$upload_status))) {
    my $row = [$page, $upload_status->{$page}];
    $csv_progress->say($fh, $row);
  }
  close($fh);
}

exit(0);

sub show_graph {
  my ($page_name) = @_;
  if (exists $page_graph_set{$page_name}) {
    # print "Already scanned $page_name\n";
    return;
  }
  my $page_path = File::Spec->catfile($config->{export_directory}, $page_name);
  if (!-e $page_path) {
    print "!!! Can't load page $page_name\n";
    return;
  }

  my $mostly_confluence_markup = load_page($page_path);
  my @links = find_page_links($mostly_confluence_markup);
  #print "Links in '$page_name' are: (@links)\n";
  foreach (@links) {
    $page_graph_set{$_} = 1;
    show_graph($_);
  }
}

sub show_features {
  my ($page_name, $page_path) = @_;
  my $mostly_confluence_markup = load_page($page_path);
  my @attachments = find_attachment_filenames($mostly_confluence_markup);
  my $has_tables = has_table_markup($mostly_confluence_markup);
  my $row = ["'$page_name'", scalar(@attachments) ? "Y" : "N", $has_tables ? "Y" : "N"];
  my $fh = *STDOUT;
  $csv->say($fh, $row);
}

sub has_table_markup {
  my $markup = shift;
  return 1 if $markup =~ /(^\|\||wikitable)/m;
  return 0;
}

sub index_attachments {
  my $rule = File::Find::Rule->new;
  my @files = $rule->in($config->{attachment_directory});
  my %lookup = (); # keyed on file name with _ in it.
  foreach (@files) {
    next if -d $_;
    my $sub_path = substr($_, $att_dir_len);
    #print "$_ sub_path $sub_path\n";
    # We're ignoring thumbnails, there isn't time to sort them out properly.
    next if $sub_path =~ m-(archive|temp|thumb|deleted)/-;
    my $file_name = basename($sub_path);
    # File names have underscores eg 9/98/A_Walk_Through_A_T5_Test_b2.png
    # markup is like [frameless|941x941px|File__A Walk Through A T5 Test v2.png]
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
    # However MediaWiki seems very lenient; a file might be called Product_Manual_v3_2.pdf with
    # a markup like [File__Product Manual v3_2.pdf]
    # There's also the case issue - A file might be called Somethingy.png and referred to in the
    # markup as [File__somethingy.png].
    # This requires a cunning plan: compress all file names by removing spaces, underscores, other
    # punctuation, and convert to lower case. Do the same transform when searching a name from
    # markup, and with luck a file will be found.
    my $attachment_compressed = compress_file_name($file_name);
    # Don't think this matters..
    # if (exists ($lookup{$attachment_compressed})) {
    #  print "Attachment (compression) collision '$attachment_compressed' with $file_name\n";
    #  print "original($file_name): $lookup{$file_name}\n\n";
    #}
    $lookup{$attachment_compressed} = $sub_path;
  }
  return %lookup;
}

sub compress_file_name {
  my $file_name = shift;
  $file_name =~ s/[ _\.,\(\)\-]+//g;
  $file_name = lc($file_name);
  return $file_name;
}

sub lookup_attachment {
  my $attachment = shift;
  # Try straight..
  if (exists $attachment_lookup{$attachment}) {
    return $attachment_lookup{$attachment};
  }
  # Try compressed..
  my $attachment_compressed = compress_file_name($attachment);
  if (exists $attachment_lookup{$attachment_compressed}) {
    return $attachment_lookup{$attachment_compressed};
  }
  return undef;
}

sub check_attachments {
  my ($page_name, $page_path) = @_;
  #print "Checking attachments for '$page_name'...\n";
  my $mostly_confluence_markup = load_page($page_path);
  my @attachments = find_attachment_filenames($mostly_confluence_markup);
  return unless(scalar @attachments);
  print "\nPage '$page_name' has " . scalar(@attachments) . " attachment(s):\n";
  my $notfounds = 0;
  foreach my $attachment (@attachments) {
    my $attachment_sub_path = lookup_attachment($attachment);
    if (defined $attachment_sub_path) {
      my $attachment_path = File::Spec->catfile($config->{attachment_directory}, $attachment_sub_path);
      if (-f $attachment_path) {
        print "++ OK! ($attachment -> $attachment_path)\n";
      } else {
        print "NOT FOUND - $attachment\n";
        $notfounds++;
      }
    } else {
      print "NOT INDEX - $attachment\n";
      $notfounds++;
    }
  }
  if ($notfounds > 0) {
    print "!! $notfounds attachment(s) could not be found in $config->{attachment_directory}\n";
  }
  print "\n";
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
  print "\n*** Checking attachment(s) existence for '$page_name'...\n";
  my $mostly_confluence_markup = load_page($page_path);
  my @attachments = find_attachment_filenames($mostly_confluence_markup);
  my $attachment_errors = 0;
  foreach my $attachment (@attachments) {
    # print "Attachment '$attachment'\n";
    my $attachment_sub_path = lookup_attachment($attachment);
    if (defined $attachment_sub_path) {
      my $attachment_path = File::Spec->catfile($config->{attachment_directory}, $attachment_sub_path);
      if (! -f $attachment_path) {
        print "  Attachment '$attachment' does not exist in the attachment directory\n";
        $attachment_errors++;
      } else {
        # print "  Attachment '$attachment' found at $attachment_path\n";
      }
    } else {
      print "  Attachment '$attachment' has no lookup entry\n";
      $attachment_errors++;
    }
  }
  if ($attachment_errors > 0) {
    warn "!!! Cannot proceed with missing attachments\n";
    return 'Missing attachments';
  }

  print "*** Converting '$page_name' to storage format...\n";

  my $lwp = LWP::UserAgent->new;
  my $base_uri = "https://$config->{confluence_host_name}/wiki/rest/api";

#  print "\n\n\n\ninitial markup.....\n\n$mostly_confluence_markup\n\n\n\n";
  my $better_confluence_markup = tweak_markup($mostly_confluence_markup);
  # print "\n\n\n\ntweaked markup.....\n\n$better_confluence_markup\n\n\n\n";


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
    warn "" . Dumper($convert_response) . "\n";
    return 'Storage format conversion failure';
  }
  # print Dumper($convert_response) . "\n";

  print "*** Uploading storage format version of '$page_name' to Confluence...\n";

  my $storage_format = $convert_response->content();
  my $storage_format_hash = decode_json $storage_format;
  my $storage_value = $storage_format_hash->{value};

#  print "\n\n\n\n\nstorage format.....\n\n$storage_value\n\n\n\n";

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
    warn "" . Dumper($content_response) . "\n";
    return 'Markup upload failure';
  }

  # print "content response: " . Dumper($content_response) . "\n";
  my $content_response_json = decode_json $content_response->content();
  my $id = $content_response_json->{id};

  my $attach_uri = "$base_uri/content/$id/child/attachment";

  print "Page '$page_name' (id $id) has " . scalar(@attachments) . " attachment(s):\n";
  foreach my $attachment (@attachments) {
    print "Uploading attachment '$attachment'\n";
    my $attachment_sub_path = lookup_attachment($attachment);
    if (defined $attachment_sub_path) {
      my $attachment_path = File::Spec->catfile($config->{attachment_directory}, $attachment_sub_path);
      # print "  path: $attachment_path\n";

      my $attachment_status = upload_attachment($attach_uri, $attachment, $attachment_path, $config->{user_name}, $config->{'api_token'});
      if (defined $attachment_status) {
        warn "Could not upload attachment '$attachment': $attachment_status\n";
        return 'Attachment upload failure';
      }
    } else {
      warn "Could not find attachment $attachment\n";
      return "Unexpected failure to find attachment $attachment";
    }
  }
  print "\n";
  return 'OK';
}

sub upload_attachment {
  my ($uri, $attachment, $attachment_path, $user_name, $api_token) = @_;

  my $cpcmd = "cp \"$attachment_path\" \"/tmp/$attachment\"";
  my ($exitCode, $stdoutLines, $stderrLines) = capture($cpcmd);
  if ($exitCode != 0) {
    print "Copy/rename of attachment $attachment failed: $cpcmd\n";
    foreach (@$stdoutLines) {
      print "OUT: $_\n";
    }
    foreach (@$stderrLines) {
      print "ERR: $_\n";
    }
    warn "Could not copy attachment.\n";
    return 'Copy failure';
  }

  my $cmd = "curl -D- -u $user_name:$api_token -X POST -H 'X-Atlassian-Token: nocheck' -F 'file=\@\"/tmp/$attachment\"' -F 'minorEdit=\"false\"' $uri";
  ($exitCode, $stdoutLines, $stderrLines) = capture($cmd);
  if ($exitCode != 0) {
    print "Upload attachment with curl failed: $cmd\n";
    foreach (@$stdoutLines) {
      print "OUT: $_\n";
    }
    foreach (@$stderrLines) {
      print "ERR: $_\n";
    }
    warn "Could not upload attachment.\n";
    return 'Upload failure';
  }

  unless (unlink("/tmp/$attachment")) {
    warn "Could not remove temporary attachment /tmp/$attachment: $!\n";
    return 'Temporary attachment deletion failure';
  }
  return undef; # All OK
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

# Run a command, capture its outputs, and return its exit code, stdout and stderr output lines (as a tuple of (int, arrayref, arrayref)).
sub capture {
  my $cmd = shift;

  package change_to_import_capture_tinys_capture_into_some_other_package;
  use Capture::Tiny ':all';
  my ($stdout, $stderr, $exitCode) = Capture::Tiny::capture {
    system($cmd);
  };

  my @stdoutLines = split('\n', $stdout);
  my @stderrLines = split('\n', $stderr);
  return ($exitCode, \@stdoutLines, \@stderrLines);
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

