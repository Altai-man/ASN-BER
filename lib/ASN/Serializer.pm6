use ASN::Types;

class ASN::Serializer {
    my %string-types = 'ASN::Types::UTF8String' => ASN::Types::UTF8String;

    multi method serialize(ASNSequence $sequence, Int $index = 48, :$debug, :$mode = Implicit) {
        my Blob $res = Buf.new;
        say "Encoding ASNSequence in $sequence.ASN-order().perl()" if $debug;
        for $sequence.ASN-order -> $field {
            my $attr = $sequence.^attributes.grep(*.name eq $field)[0];
            # Params
            my %params;
            %params<name> = $field;
            %params<default> = $attr.default-value if $attr ~~ DefaultValue;
            %params<tag> = $attr.tag if $attr ~~ CustomTagged;
            my $value = $attr.get_value($sequence);

            next if $attr ~~ Optional && (!$value.defined || $value ~~ Positional && $value.elems == 0);

            %params<value> = $value;
            if $attr ~~ ASN::Types::UTF8String {
                %params<type> = ASN::Types::UTF8String;
            } elsif $attr ~~ ASN::Types::OctetString {
                %params<type> = ASN::Types::OctetString;
            }
            $res.push(self.serialize(ASNValue.new(|%params), :$debug, :$mode));
        }
        Blob.new(|($index == -1 ?? () !! ($index, |self!calculate-len($res))), |$res);
    }

    method !calculate-len(Blob $value, :$infinite) {
        with $infinite {
            return Buf.new(128);
        }
        if $value.elems <= 127 {
            return Buf.new($value.elems);
        }
        my $long = self.serialize($value.elems, -1);
        if $long.elems > 126 {
            die "The value is too long, please use streaming";
        }
        return Buf.new($long.elems + 128, |$long);
    }

    # INTEGER
    multi method serialize(Int $int is copy where $int.HOW ~~ Metamodel::ClassHOW, Int $index = 2, :$debug, :$mode) {
        my $int-encoded = Buf.new;
        my $bit-shift-value = 0;
        my $bit-shift-mask = 0xff;
        while True {
            my $byte = $int +& $bit-shift-mask +> $bit-shift-value;
            if $byte == 0 {
                $int-encoded.append(0) if $int-encoded.elems == 0;
                last;
            }
            $int-encoded.append($byte);
            # Update operands
            $bit-shift-value += 8;
            $bit-shift-mask +<= 8;
        }

        say "Encoding Int ($int) with index $index, resulting in $int-encoded.reverse().perl()" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($int-encoded))), |$int-encoded.reverse);
    }

    # NULL
    multi method serialize(ASN-Null, Int $index = 5, :$debug, :$mode) {
        Buf.new(|($index == -1 ?? () !! ($index, 0)));
    }

    # BOOLEAN
    multi method serialize(Bool $bool, Int $index = 1, :$debug, :$mode) {
        say "Encoding Bool ($bool with index $index" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, 1)), $bool ?? 255 !! 0);
    }

    # ENUMERATED
    multi method serialize($enum-value where $enum-value.HOW ~~ Metamodel::EnumHOW, Int $index = 10, :$debug, :$mode) {
        my $encoded = $enum-value.^enum_values.Hash{$enum-value};
        say "Encoding Enum ($enum-value) with index $index, resulting in $encoded" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, 1)), $encoded);
    }

    # UTF8String
    multi method serialize(ASN::Types::UTF8String $str, Int $index = 12, :$debug) {
        my $encoded = Buf.new($str.value.encode);
        say "Encoding UTF8String ($str.value() with index $index, resulting in $encoded.perl()" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($encoded))), |$encoded);
    }

    # OctetString
    multi method serialize(ASN::Types::OctetString $str, Int $index = 4, :$debug) {
        my $buf =  Buf.new($str.value.comb(2).map('0x' ~ *).map(*.Int));
        say "Encoding OctetString ($str.value() with index $index, resulting in $buf.perl()" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($buf))), |$buf);
    }

    # Positional
    multi method serialize(Positional $sequence, Int $index is copy = 16, :$debug, :$mode) {
        # COMPLEX element, so add 32
        $index += 32 if $index != -1;
        my $temp = Buf.new;
        say "Encoding Sequence ($sequence.perl()) with index $index into:" if $debug;
        for @$sequence -> $attr {
            $temp.append(self.serialize($attr, :$debug, :$mode));
        }
        # Tag + Length + Value
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($temp))), |$temp);
    }

    # Common method to enforce custom traits for ASNValue value
    # and call a serializer
    multi method serialize(ASNValue $asn-node, :$debug, :$mode) {
        my $value = $asn-node.value;

        # Don't serialize undefined values of type with a default
        return Buf.new if $asn-node.default eqv $value;
        return self.serialize($asn-node.type.new($value), :$debug, :$mode) if $value ~~ Str;

        if $value ~~ Positional {
            $value = $value.map({
                if $asn-node.type ~~ ASN::Types::UTF8String {
                    ASN::Types::UTF8String.new($_);
                } elsif $asn-node.type ~~ ASN::Types::OctetString {
                    ASN::Types::OctetString.new($_);
                } else {
                    $_;
                }
            });
        }
        self.serialize($value, |( $_ + 128 with $asn-node.tag), :$debug, :$mode);
    }

    # CHOICE
    multi method serialize(ASNChoice $choice, :$debug, :$mode) {
        my $description = $choice.ASN-choice;
        my $choice-item = $description{$choice.ASN-value.key};
        unless $description{$choice.ASN-value.key}:exists {
            die "Could not find value by $choice.ASN-value().key() out of $description.perl()";
        }
        my $value = $choice.ASN-value.value;

        my $index = do given $mode {
            when Implicit {
                if $choice-item ~~ Pair {
                    $choice-item.key + 128;
                } else {
                    $choice-item.ASN-tag-value + 64;
                }
            }
        }
        $index += 32 unless $value ~~ $primitive-type;

        my $inner = self.serialize($value, -1, :$debug, :$mode);
        say "Encoding ASNChoice by $description.perl() with value: $value.perl()" if $debug;
        Buf.new(|($index == -1 ?? () !! ($index, |self!calculate-len($inner))), |$inner);
    }

    # Dying method to detect types not yet implemented
    multi method serialize($common, :$debug) {
        die "NYI for: $common.perl()";
    }
}