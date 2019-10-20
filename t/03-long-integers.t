use ASN::Parser;
use Test;

my $buf = Buf.new(255, 255, 255, 128);
is ASN::Parser.parse($buf, Int), -128, 'Parsing of a padded negative value works';

use ASN::Serializer;

say ASN::Serializer.serialize(127);

done-testing;
