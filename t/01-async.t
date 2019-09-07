use ASN::Types;
use ASN::Parser::Async;
use Test;

enum Fuel <Solid Liquid Gas>;

class SpeedChoice does ASNChoice {
    method ASN-choice() {
        { mph => (1 => Int), kmph => (0 => Int) }
    }
}

class Rocket does ASNSequence {
    has Str $.name is UTF8String;
    has Str $.message is UTF8String is default-value("Hello World") is optional;
    has Fuel $.fuel;
    has SpeedChoice $.speed is optional;
    has ASNSequenceOf[ASN::Types::UTF8String] $.payload;

    method ASN-order() {
        <$!name $!message $!fuel $!speed $!payload>
    }
}

my $one-rocket-ber = Buf.new(
        0x30, 0x1B,
        0x0C, 0x06, 0x46, 0x61, 0x6C, 0x63, 0x6F, 0x6E,
        0x0A, 0x01, 0x00,
        0x81, 0x02, 0x46, 0x50, 0x30, 0x0A,
        0x0C, 0x03, 0x43, 0x61, 0x72,
        0x0C, 0x03, 0x47, 0x50, 0x53);

my $one-and-a-half = $one-rocket-ber ~ Buf.new(
        0x30, 0x1B,
        0x0C, 0x06, 0x46, 0x61, 0x6C, 0x63, 0x6F, 0x6E,
        0x0A, 0x01, 0x00,
        0x81, 0x02, 0x46, 0x50, 0x30, 0x0A,
        0x0C, 0x03, 0x43, 0x61, 0x72,
        0x0C, 0x03, 0x47, 0x50); # Second one

my $parser = ASN::Parser::Async.new(type => Rocket);

my $counter = 0;
my $p = Promise.new;

$parser.values.tap({ $counter++; $p.keep if $counter ~~ 3 });

$parser.process($one-and-a-half);
$parser.process(Buf.new(0x53));

my $long-rocket-ber = Buf.new(
        0x30, 0x82, 0x01, 0x1F, # tag and length
        ) ~ Buf.new(0x0C, 0x82, 0x01, 0x08) ~ ([~] ("Falcon".encode xx 44)) ~
        Buf.new(
                0x0A, 0x01, 0x00,
                0x81, 0x02, 0x46, 0x50, 0x30, 0x0A,
                0x0C, 0x03, 0x43, 0x61, 0x72,
                0x0C, 0x03, 0x47, 0x50, 0x53);

# send a long rocket buf byte-by-byte to ensure we can
# parse it however e.g. the network
# can split it
$parser.process(Buf.new($_)) for @$long-rocket-ber;

await Promise.anyof([$p, Promise.in(5)]);

$parser.close;
ok $p.status ~~ Kept, "Parsed three rockets";

done-testing;
