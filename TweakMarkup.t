use strict;
use warnings FATAL => 'all';
use Test::More qw(no_plan);
no warnings 'experimental::smartmatch';
use lib '.';
use TweakMarkup;

# 1. Detect attachment filenames
{
  my $markup = <<'EOF';
This is [File__MyImage.png] embedded in it not once but [File__MyImage.png] <b>twice</b>.
Another [File__OtherImage.png] image. And a doc with an escaped name [File__T&amp;m-wo.doc].
* [Complicated Specification Document v2.2 (pdf)|File__ComplicatedInterfaceSpec2.2.pdf]
* [frameless|941x941px|File__A Walk Through A T5 Test v2.png]

EOF

  my @atts = find_attachment_filenames($markup);
  for my $att (@atts) {
    print "att [$att]\n";
  }
  is_deeply(\@atts, ['MyImage.png', 'MyImage.png', 'OtherImage.png', 'T&m-wo.doc', 'ComplicatedInterfaceSpec2.2.pdf', 'A Walk Through A T5 Test v2.png'], 'find_attachment_filenames');
}

# 2. Markup: Bold
{
  my $markup = "blah <b>markup</b> and <b>more</b> blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah *markup* and *more* blah";
  ok($tweaked eq $expected);
}

# 3. Markup: Image file link
{
  my $markup = "blah [File__MyImage.png] and [File__MyImage.png] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah !MyImage.png! and !MyImage.png! blah";
  ok($tweaked eq $expected);
}

# 4. Markup: Bold '''
{
  my $markup = "blah '''markup''' and '''more''' blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah *markup* and *more* blah";
  ok($tweaked eq $expected);
}

# 5. Markup: Bold italic '''''
{
  my $markup = "blah '''''markup''''' and '''''more''''' blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah *_markup_* and *_more_* blah";
  ok($tweaked eq $expected);
}

# 6. Markup: {code}..{code} to {{..}}
{
  my $markup = "blah {code}monospaced{code} and {code}foo{code} blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah {{monospaced}} and {{foo}} blah";
  ok($tweaked eq $expected);
}

# 7. Images: no frameless/dimensions, just name
{
  my $markup = "blah [frameless|941x941px|File__A Walk Through A T5 Test v2.png] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah !A Walk Through A T5 Test v2.png! blah";
  ok($tweaked eq $expected);
}

# 8. Images: Removal of frameless
{
  my $markup = "blah [frameless|File__A Walk Through A T5 Test v2.png] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah !A Walk Through A T5 Test v2.png! blah";
  ok($tweaked eq $expected);
}

# 9. Images: Removal of frameless & empty dimension
{
  my $markup = "blah [400px||SCOM2|File__SCOM2.PNG] blah"; # ALT text?
  my $tweaked = tweak_markup($markup);
  my $expected = "blah !SCOM2.PNG! blah";
  ok($tweaked eq $expected);
}

# 10. Images: Removal of all options
{
  my $markup = "blah [none|thumb|536x536px|File__Import2.png] blah"; # ALT text?
  my $tweaked = tweak_markup($markup);
  my $expected = "blah !Import2.png! blah";
  ok($tweaked eq $expected);
}

# 11. Links: escaped name
{
  my $markup = "blah [File__T&amp;m-wo.doc] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [^T&m-wo.doc] blah";
  ok($tweaked eq $expected);
}

# 12. Links: plain name
{
  my $markup = "blah [File__Document.doc] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [^Document.doc] blah";
  ok($tweaked eq $expected);
}

# 13. Links: friendly and file name
{
  my $markup = "blah [Complicated Specification Document v2.2 (pdf)|File__ComplicatedInterfaceSpec2.2.pdf] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [Complicated Specification Document v2.2 (pdf)|^ComplicatedInterfaceSpec2.2.pdf] blah";
  ok($tweaked eq $expected);
}

# 14. Links: no thumbnails, just name
{
  my $markup = "blah [frameless|File__API Documentation.doc] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [^API Documentation.doc] blah";
  ok($tweaked eq $expected);
}


# 15. Links: friendly name and URL
{
  my $markup = "blah [Acme Corporation|https://www.acme.com/] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [Acme Corporation|https://www.acme.com/] blah";
  ok($tweaked eq $expected);
}

# 16. Links: friendly name (single word) and URL 2
{
  my $markup = "blah [Ubercorp|https://www.u.com/] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [Ubercorp|https://www.u.com/] blah";
  ok($tweaked eq $expected);
}

# 17. Links: friendly name and URL 3
{
  my $markup = "blah [New Mobile Operator Guide (pdf)|http://www.mnposg.org.uk/Main_Documents/New%20Mobile%20Operator%20Guide%201.1.pdf] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [New Mobile Operator Guide (pdf)|http://www.mnposg.org.uk/Main_Documents/New%20Mobile%20Operator%20Guide%201.1.pdf] blah";
  ok($tweaked eq $expected);
}

# 18. Just URL with no square brackets. Square brackets unnecessary.
{
  my $markup = "blah https://www.acme.com blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah https://www.acme.com blah";
  ok($tweaked eq $expected);
}

# 19. Just URL with square brackets
{
  my $markup = "blah [https://www.acme.com] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [https://www.acme.com] blah";
  ok($tweaked eq $expected);
}



