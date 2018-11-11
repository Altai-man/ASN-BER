role Optional {}

role Choice[:$choice-of] {
    method get-choice(--> Array) { $choice-of }
}

role DefaultValue[:$default-value] {
    method get-default() { $default-value }
}

multi trait_mod:<is>(Attribute $attr, :$optional) is export {
    $optional does Optional;
}

multi trait_mod:<is>(Attribute $attr, :$choice-of!) is export {
    $attr does Choice[:$choice-of];
}

multi trait_mod:<is>(Attribute $attr, :$default-value) is export {
    $attr does DefaultValue[:$default-value];
}

class ASNValue {
    has $.default;
    has %.choice;
    has $.optional = False;
    has $.value;
}

class Serializator {
    multi method serialize(Int $index, $common where $common.HOW ~~ Metamodel::EnumHOW) {
        Buf.new($index, 1, $common.^enum_values.Hash{$common});
    }

    method serialize-choice(Int $index is copy, $common, $choice-of) {
        # It is a complex type, so plus 0b10100000
        $index += 0x20;
        my $inner-index = 0x80; # Starting number for inner structures.
        my $common-key = $common.key;
        for $choice-of.map(*.key) -> $key {
            last if $key eq $common-key;
            $inner-index++;
        }
        my $inner = self.serialize($inner-index, $common.value);
        Buf.new($index, $inner.elems, |$inner);
    }

    multi method serialize(Int $index, Int $int is copy where $int.HOW ~~ Metamodel::ClassHOW) {
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
        Buf.new($index, $int-encoded.elems, |$int-encoded.reverse);
    }

    multi method serialize(Int $index is copy, Array $sequence) {
        # 0x30 is sequence tag
        my $result = Buf.new(0x30);

        my $temp = Buf.new;
        my $index = 0x80; # index for sequence elements is context-specific, so "0b10000000"
        for @$sequence -> $attr {
            $temp.append(self.serialize($index, $attr));
            $index++;
        }
        # Tag + Length + Value
        Buf.new(|$result, $temp.elems, |$temp);
    }

    multi method serialize(Int $index, ASNValue $common is copy) {
        my $value = $common.value;
        return Buf.new if $common.default.defined && !$value.defined;
        if $common.choice.elems > 0 {
            $value does Choice[choice-of => $_] with $common.choice;
        }
        $value does DefaultValue[default-value => $_] with $common.default;
        $value does Optional if $common.optional;
        $common.choice.elems == 0 ??
                self.serialize($index, $value) !!
                self.serialize-choice($index, $value, $common.choice);
    }

    multi method serialize(Int $index, $common) {
        die "NYI for: $common";
    }

    multi method serialize(Int $index, Str $str) {
        Buf.new($index, $str.chars, |$str.encode);
    }
}

role ASNType {
    method order(--> Array) {...}

    method serialize(--> Blob) {
        my @values;
        for self.order -> $field {
            my $attr = self.^attributes.grep(*.name eq $field)[0];
            # Params
            my %params;
            %params<default> = $attr.get-default if $attr ~~ DefaultValue;
            %params<choice> = $attr.get-choice if $attr ~~ Choice;
            %params<optional> = True if $attr ~~ Optional;
            %params<value> = $attr.get_value(self);
            @values.push(ASNValue.new(|%params));
        }
        Blob.new(Serializator.serialize(0x30, @values));
    }
}
