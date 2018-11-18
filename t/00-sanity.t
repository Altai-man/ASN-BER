use ASN::Types;
use ASN::BER;
use Test;

enum Fuel <Solid Liquid Gas>;

class Rocket does ASNType {
    has Str $.name;
    has Str $.message is default-value("Hello World");
    has Fuel $.fuel;
    has $.speed is choice-of(mph => Int, kmph => Int) is optional;
    has Str @.payload is sequence-of(Str);

    method order() {
        <$!name $!message $!fuel $!speed @!payload>
    }
}

# Set complex always
# If context is universal, add type
# If context is specific(inside of sequence, set or choice), type is erased.

# (30 1D - universal, complex, sequence(16)
#     (80 06 - context-specific, start from 0
#         (46 61 6C, 63 6F 6E - fal,con))
#     (82 01 (00 fuel)) - context-specific, 2
#     (A3 04 - context-specific, complex, 3 is because of index
#         (80 02 (mph 46 50 18000))) - context-specific, simple, 0 because of enum index
#     (A4 0A - context-specific, complex, 4 is because of index
#         (0C 03 (43 61 72)) - universal, 12 is UTF8String type
#         (0C 03 (47 50 53)) - universal, 12 is UTF8String type
#         )
#     )

my $rocket-ber = Blob.new(0x30, 0x1D, 0x80, 0x06, 0x46, 0x61, 0x6C,
        0x63, 0x6F, 0x6E, 0x82, 0x01, 0x00, 0xA3,
        0x04, 0x80, 0x02, 0x46, 0x50, 0xA4, 0x0A,
        0x0C, 0x03, 0x43, 0x61, 0x72, 0x0C, 0x03,
        0x47, 0x50, 0x53);

my $rocket = Rocket.new(name => 'Falcon', fuel => Solid,
        speed => mph => 18000,
        payload => ["Car", "GPS"]);

is-deeply $rocket.serialize, $rocket-ber, "Correctly serialized a Rocket";

is-deeply Rocket.parse($rocket-ber), $rocket, "Correctly parsed a Rocket";

done-testing;
