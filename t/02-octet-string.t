use Test;
use ASN::Serializer;
use ASN::Parser;
use ASN::Types;

class Rocket does ASNSequence {
    has $.name is OctetString;

    method ASN-order() {
        <$!name>
    }
}

my $rocket = Rocket.new(name => 'Falcon');

my $rocket-ber = Buf.new(
        0x30, 0x08,
        0x04, 0x06, 0x46, 0x61, 0x6C, 0x63, 0x6F, 0x6E);

is-deeply ASN::Serializer.serialize($rocket, :mode(Implicit)), $rocket-ber, "Correctly serialized a Rocket in implicit mode";

my $parsed = ASN::Parser.new(type => Rocket).parse($rocket-ber, :mode(Implicit));
is $parsed.name, 'Falcon'.encode, 'Correctly parsed out Rocket';

$rocket = Rocket.new(name => Blob.new('Falcon'.encode));

is-deeply ASN::Serializer.serialize($rocket, :mode(Implicit)), $rocket-ber, "Correctly serialized a Rocket in implicit mode";

is-deeply ASN::Parser
        .new(type => Rocket)
        .parse($rocket-ber, :mode(Implicit)),
        $rocket, "Correctly parsed a Rocket in implicit mode";

done-testing;
