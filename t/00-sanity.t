use ASN::BER;
use Test;

enum Fuel <Solid Liquid Gas>;

class Rocket does ASNType {
    has Str $.name;
    has Str $.message is default-value("Hello World");
    has Fuel $.fuel;
    has $.speed is choice-of([mph => Int, kmph => Int]) is optional;
    has Str @.payload;

    method order() { <$!name $!message $!fuel $!speed @!payload> }
}

my $rocket-ber = Blob.new(0x30, 0x1D, 0x80, 0x06, 0x46, 0x61, 0x6C,
        0x63, 0x6F, 0x6E, 0x82, 0x01, 0x00, 0xA3,
        0x04, 0x80, 0x02, 0x46, 0x50, 0xA4, 0x0A,
        0x0C, 0x03, 0x43, 0x61, 0x72, 0x0C, 0x03,
        0x47, 0x50, 0x53);

is-deeply Rocket.new(name => 'Falcon', fuel => Solid,
              speed => mph => 18000,
              payload => <Car GPS>).serialize, $rocket-ber, "Correctly serialized a Rocket";

done-testing;
