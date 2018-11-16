enum TagClass <Universal Application Context Private>;

role Optional {}

role Choice[:$choice-of] {
    method get-choice() { $choice-of }
}

role DefaultValue[:$default-value] {
    method get-default() { $default-value }
}

role SequenceOf[:$sequence-of] {
    method get-sequence-type() { $sequence-of }
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

multi trait_mod:<is>(Attribute $attr, :$sequence-of) is export {
    $attr does SequenceOf[:$sequence-of];
}


class ASNValue {
    has $.default;
    has $.choice;
    has $.optional = False;
    has $.value;
    has $.sequence-of;
}

class Serializator {
    multi method serialize(Int $index, $common where $common.HOW ~~ Metamodel::EnumHOW, TagClass $class) {
        Buf.new($index, 1, $common.^enum_values.Hash{$common});
    }

    method serialize-choice(Int $index, $common, $choice-of, TagClass $class) {
        # It is a complex type, so plus 0b10100000
        my $inner-index = 0x80; # Starting number for inner structures.
        my $common-key = $common.key;
        for @$choice-of -> $key {
            if $key.key eq $common-key {
                last
            } else {
                $inner-index++;
            }
        }
        my $inner = self.serialize($inner-index, $common.value, $class);
        Buf.new($index +| 0x20, $inner.elems, |$inner);
    }

    multi method serialize(Int $index, Int $int is copy where $int.HOW ~~ Metamodel::ClassHOW, TagClass $class) {
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

    multi method serialize(Int $index, Array $sequence, TagClass $class) {
        my $delta = do given $class {
            when Application {
                16;
            }
            when Context {
                0
            }
        }

        my $result = Buf.new($index +| $delta +| 32); # Enable complex type bits (32)

        my $temp = Buf.new;
        my $inner-index = do given $class {
            when Application { 0x80 }
            when Context { 0 }
        }
        for @$sequence -> $attr {
            $temp.append(self.serialize($inner-index, $attr, $sequence ~~ SequenceOf ?? Application !! Context));
            $inner-index++ if $sequence !~~ SequenceOf;
        }
        # Tag + Length + Value
        Buf.new(|$result, $temp.elems, |$temp);
    }

    multi method serialize(Int $index, ASNValue $common, TagClass $class) {
        my $value = $common.value;
        # Don't serialize undefined values of type with a default
        return Buf.new if $common.default.defined && !$value.defined;

        if $common.choice ~~ List {
            $value does Choice[choice-of => $common.choice];
        }
        $value does DefaultValue[default-value => $_] with $common.default;
        $value does Optional if $common.optional;
        unless $common.sequence-of =:= Any {
            $value does SequenceOf[sequence-of => $_];
        }
        $common.choice !~~ List ??
                self.serialize($index, $value, $class) !!
                self.serialize-choice($index, $value, $common.choice, $class);
    }

    multi method serialize(Int $index, $common, TagClass $class) {
        die "NYI for: $common";
    }

    multi method serialize(Int $index, Str $str, TagClass $class) {
        my $delta = do given $class {
            when Application { 12 }
            when Context { 0 }
        }
        Buf.new($index +| $delta, $str.chars, |$str.encode);
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
            $attr.get-sequence-type if $attr ~~ SequenceOf;
            %params<sequence-of> = $attr.get-sequence-type if $attr ~~ SequenceOf;
            %params<value> = $attr.get_value(self);
            @values.push(ASNValue.new(|%params));
        }
        my $class = Application;
        Blob.new(Serializator.serialize(0x0, @values, $class));
    }
}
