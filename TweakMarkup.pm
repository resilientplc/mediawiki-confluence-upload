use warnings FATAL => 'all';
use strict;
use HTML::Entities qw(decode_entities);

use Exporter qw(import);

our @EXPORT = qw(tweak_markup find_attachment_filenames);

# Fixes up some markup conversions that the Universal Wiki Converter doesn't quite get right.
# (Converting from MediaWiki to Confluence markup).
# Input: Confluence markup (with bits of Mediawiki markup)
# Output: Proper Confluence markup
sub tweak_markup {
    my $markup = shift; # a big string of Confluence markup
    #warn "MARKUP: \n\n\n$markup\n\n\n\n";

    # [File__foo.txt] -> !foo.txt!
    $markup =~ s/\[File__([^\]]+?)\]/!${\(decode_entities($1))}!/g;

    # [Friendly name|File__foo.txt] -> [Friendly name^foo.txt]
    $markup =~ s/\[([^|]+?)\|File__([^\]]+?)\]/[$1^${\(decode_entities($2))}]/g;

    # <b>...</b> -> *...*
    $markup =~ s/<b>(.*?)<\/b>/*$1*/g; 

    # {code} ... {code} -> {panel:borderStyle=dashed|borderColor=blue} ... {panel}
    $markup =~ s/\{code\}(\S.*?\S)\{code\}/\{{$1}}/gs;
    return $markup;
}

# Find all attachment filenames.
# Input: Confluence markup (with bits of Mediawiki markup)
# Output: all attachment filenames
sub find_attachment_filenames {
    my $markup = shift; # a big string of Confluence markup (?:[^|]+?\|)?
    my @attachments = ($markup =~ /\[(?:.*?|)?File__([^\]]+?)\]/g);
    # print "attachments is @attachments\n";
    my @decoded = map { decode_entities($_) } @attachments;
    # print "Decoded is @decoded\n";
    return @decoded;
}
1;
