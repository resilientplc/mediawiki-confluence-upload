use strict;
use warnings FATAL => 'all';
use Test::More tests => 2;
no warnings 'experimental::smartmatch';
use lib '.';
use TweakMarkup;

my $markup = <<'EOF';
  This is some <b>markup</b> with an [File__MyImage.png] embedded in it not once but [File__MyImage.png] <b>twice</b>.
  '''Here''' is '''''another''''' [File__OtherImage.png] <b>image</b> that's {code}wrong{code}. And a doc with an escaped name [File__T&amp;m-wo.doc].
* [Complicated Specification Document v2.2 (pdf)|File__ComplicatedInterfaceSpec2.2.pdf]

EOF

my $tweaked = tweak_markup($markup);
my $expected = <<'EOF';
  This is some *markup* with an !MyImage.png! embedded in it not once but !MyImage.png! *twice*.
  *Here* is _another_ !OtherImage.png! *image* that's {{wrong}}. And a doc with an escaped name !T&m-wo.doc!.
* [Complicated Specification Document v2.2 (pdf)^ComplicatedInterfaceSpec2.2.pdf]

EOF

warn "tweaked\n=====\n$tweaked\n=====\n";
warn "expected\n=====\n$expected\n=====\n";
ok($tweaked eq $expected);



my @atts = find_attachment_filenames($markup);
print "atts is (@atts)\n";
is_deeply(\@atts, ['MyImage.png', 'MyImage.png', 'OtherImage.png', 'T&m-wo.doc', 'ComplicatedInterfaceSpec2.2.pdf'], 'find_attachment_filenames');
