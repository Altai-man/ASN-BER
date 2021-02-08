use ASN::Parser;
use Test;

my $buf = Buf.new(255, 255, 255, 128);
is ASN::Parser.parse($buf, Int), -128, 'Parsing of a padded negative value works';

use ASN::Serializer;

my @nums = 0, 127, 128, 256, -128, -129;
my @results = (Buf.new(0x02, 0x01, 0x00), Buf.new(0x02, 0x01, 0x7F),
               Buf.new(0x02, 0x02, 0x00, 0x80),
               Buf.new(0x02, 0x02, 0x01, 0x00),
               Buf.new(0x02, 0x01, 0x80),
               Buf.new(0x02, 0x02, 0xFF, 0x7F));

for @nums Z @results {
    is-deeply $_[1], ASN::Serializer.serialize($_[0]), "Can serialize $_[0].raku() into $_[1].raku()";
}

done-testing;
