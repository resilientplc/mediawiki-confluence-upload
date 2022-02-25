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
    # print "MARKUP 1: \n$markup\n";

    # Only for File__ attachments...
    # [frameless|941x941px|File__A Walk Through A T5 Test v2.png] -> (get rid of frameless & dimensions)
    # [frameless|File__A Walk Through A T5 Test v2.png] -> (get rid of frameless)
    # [400px||SCOM2|File__SCOM2.PNG]
    # [none|thumb|536x536px|File__Import2.png]
    # [511x511px|File__Import.png]
    $markup =~ s/\[\S+?(\|\S*?)*(?=\|File__)\|/\[/g;
    # print "MARKUP 2: \n$markup\n";

    # Decoded entities:
    # [File__T&amp;m-wo.doc] -> [File__T&m-wo.doc]
    $markup =~ s/\[File__(.*)\]/[File__${\(decode_entities($1))}]/g;
    # print "MARKUP 3: \n$markup\n";

    # Images:
    # [File__foo.png] -> !File__foo.png!
    # Files:
    # [File__foo.docx] -> [File__foo.docx]
    $markup =~ s/(\[File__([^\]]+?)\])/${\(pling_for_image($1))}/g;
    # print "MARKUP 4: \n$markup\n";

    # Attachments without friendly names; just the filename:
    # [File__9030346-BAU-BillingProcesses.pdf]
    # [File__Test Strategy.docx]
    # -> [^Test Criteria and Examples.pdf]
    $markup =~ s/\[(File__.+?)\]/[^$1]/g;
    # print "MARKUP 5: \n$markup\n";

    # Attachments and links with friendly names:
    # [Test Criteria and Examples (pdf)|File__Test Criteria and Examples.pdf]
    # -> [Test Criteria and Examples (pdf)|^Test Criteria and Examples.pdf]
    # (note the inclusion of the caret ----^ for attachments)
    # [Acme Corporation|https://www.acme.com] -> [Acme Corporation|https://www.acme.com]
    # [Ubercorp|https://www.u.com] -> [Ubercorp|https://www.u.com]
    # (note the absence of caret for links)
    $markup =~ s/\[(.+?)\|(File__.+?)\]/[$1|^$2]/g;
    $markup =~ s/\[(.+?)\|((?!File__).+?)\]/[$1|$2]/g;
    # print "MARKUP 6: \n$markup\n";

    # Images: !foo with spaces.txt! -> !foo_with_spaces.txt!
    #$markup =~ s/!(.*?)!/!${\(space_to_underscore($1))}!/g;
    # print "MARKUP 7: \n$markup\n";

    $markup =~ s/File__//g;
    # print "MARKUP 8: \n$markup\n";



    # <b>...</b> -> *...*
    $markup =~ s/<b>(.*?)<\/b>/*$1*/g; 

    # {code}...{code} -> {{...}}
    $markup =~ s/\{code\}(\S.*?\S)\{code\}/\{{$1}}/gs;

    # '''''...''''' -> *_..._*
    $markup =~ s/'''''(.*?)'''''/*_$1_*/g; 

    # '''...''' -> *...*
    $markup =~ s/'''(.*?)'''/*$1*/g; 

    # ''...'' -> _..._
    $markup =~ s/''(.*?)''/_$1_/g; 

    # {{<nowiki>...</nowiki>}} -> {{...}}
    $markup =~ s/\{\{<nowiki>(.*?)<\/nowiki>\}\}/\{{$1}}/g;

    # print "MARKUP END: \n$markup\n";

    return $markup;
}

sub space_to_underscore {
    my $spaces = shift;
    $spaces =~ s/ /_/g;
    return $spaces;
}

sub pling_for_image {
    my $file = shift; # [potential friendly name|File__something.suffix]
    if ($file =~ /\.(jpg|png|gif)\]$/i) {
        $file =~ s/^\[/!/;
        $file =~ s/\]$/!/;
        return $file;
    } else {
        return $file
    }
}

sub links_for_non_image {
    my $file = shift;
    if ($file =~ /\.(jpg|png|gif)$/i) {
        return $file;
    } else {
        return "LinkTest^$file"; # May need "Wiki Page Name^$file" ?
    }
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
