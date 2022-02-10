use strict;
use warnings FATAL => 'all';
use Test::More tests => 9;
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

# 7. Links: escaped name
{
  my $markup = "blah [File__T&amp;m-wo.doc] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah !T&m-wo.doc! blah";
  ok($tweaked eq $expected);
}

# 8. Links: friendly and file name
{
  my $markup = "blah [Complicated Specification Document v2.2 (pdf)|File__ComplicatedInterfaceSpec2.2.pdf] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah [Complicated Specification Document v2.2 (pdf)^ComplicatedInterfaceSpec2.2.pdf] blah";
  ok($tweaked eq $expected);
}

# 9. Links: no thumbnails, just name
{
  my $markup = "blah [frameless|941x941px|File__A Walk Through A T5 Test v2.png] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah !A_Walk_Through_A_T5_Test_v2.png! blah";
  ok($tweaked eq $expected);
}

