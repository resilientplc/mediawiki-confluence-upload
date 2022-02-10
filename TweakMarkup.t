use strict;
use warnings FATAL => 'all';
use Test::More tests => 4;
no warnings 'experimental::smartmatch';
use lib '.';
use TweakMarkup;

# 1. Big markup test (to be split up)
{
  my $markup = <<'EOF';
  This is some <b>markup</b> with an [File__MyImage.png] embedded in it not once but [File__MyImage.png] <b>twice</b>.
  '''Here''' is '''''another''''' [File__OtherImage.png] <b>image</b> that's {code}wrong{code}. And a doc with an escaped name [File__T&amp;m-wo.doc].
* [Complicated Specification Document v2.2 (pdf)|File__ComplicatedInterfaceSpec2.2.pdf]
* [frameless|941x941px|File__A Walk Through A T5 Test v2.png]

EOF

  my $tweaked = tweak_markup($markup);
  my $expected = <<'EOF';
  This is some *markup* with an !MyImage.png! embedded in it not once but !MyImage.png! *twice*.
  *Here* is *_another_* !OtherImage.png! *image* that's {{wrong}}. And a doc with an escaped name !T&m-wo.doc!.
* [Complicated Specification Document v2.2 (pdf)^ComplicatedInterfaceSpec2.2.pdf]
* !A_Walk_Through_A_T5_Test_v2.png!

EOF

  warn "tweaked\n=====\n$tweaked\n=====\n";
  warn "expected\n=====\n$expected\n=====\n";
  ok($tweaked eq $expected);
}


# 2. Detect attachment filenames
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

# 3. Markup: Bold
{
  my $markup = "blah <b>markup</b> blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah *markup* blah";
  ok($tweaked eq $expected);
}

# 4. Markup: Image file link
{
  my $markup = "blah [File__MyImage.png] blah";
  my $tweaked = tweak_markup($markup);
  my $expected = "blah !MyImage.png! blah";
  ok($tweaked eq $expected);
}