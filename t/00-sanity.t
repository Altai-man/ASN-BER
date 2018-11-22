use ASN::Types;
use ASN::BER;
use Test;

enum Fuel <Solid Liquid Gas>;

class Rocket does ASNType {
    has ASN::UTF8String $.name;
    has ASN::UTF8String $.message is default-value("Hello World");
    has Fuel $.fuel;
    has $.speed is choice-of(mph => (1 => Int), kmph => (0 => Int)) is optional;
    has Str @.payload is sequence-of(Str);

    method ASN-order() {
        <$!name $!message $!fuel $!speed @!payload>
    }
}

# (30 1B - universal, complex, sequence(16)
#     (0C 06 - UTF8String type
#         (46 61 6C, 63 6F 6E - fal,con))
#     (0A 01 (00 fuel)) - ENUMERATION type
#     (81 02 <- 80 + tag set
#         (mph 46 50 (== 18000))) - context-specific, simple, 0 because of enum index
#     (30 0A - universal, complex, sequence(16)
#         (0C 03 (43 61 72)) - <- UTF8String type
#         (0C 03 (47 50 53)) - <- UTF8String type
#     )
# )

my $rocket-ber = Blob.new(
        0x30, 0x1B,
        0x0C, 0x06, 0x46, 0x61, 0x6C, 0x63, 0x6F, 0x6E,
        0x0A, 0x01, 0x00,
        0x81, 0x02, 0x46, 0x50, 0x30, 0x0A,
        0x0C, 0x03, 0x43, 0x61, 0x72,
        0x0C, 0x03, 0x47, 0x50, 0x53);

my $rocket = Rocket.new(name => 'Falcon', fuel => Solid,
        speed => mph => 18000,
        payload => ["Car", "GPS"]);

is-deeply $rocket.serialize(:implicit), $rocket-ber, "Correctly serialized a Rocket in implicit mode";

is-deeply Rocket.parse($rocket-ber, :implicit), $rocket, "Correctly parsed a Rocket in implicit mode";

done-testing;
