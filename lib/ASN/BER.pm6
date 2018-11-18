use ASN::Types;
use ASN::Serializator;
use ASN::Parser;

role ASNType {
    method order(--> Array) {...}

    method !prepare-fields(:$for-parsing) {
        my @values;
        for self.order -> $field {
            my $attr = self.^attributes.grep(*.name eq $field)[0];
            # Params
            my %params;
            %params<name> = $field;
            %params<default> = $attr.default-value if $attr ~~ DefaultValue;
            %params<choice> = $attr.get-choice if $attr ~~ Choice;
            %params<optional> = True if $attr ~~ Optional;
            %params<sequence-of> = $attr.get-sequence-type if $attr ~~ SequenceOf;
            if $for-parsing {
                %params<type> = $attr.type;
            } else {
                %params<value> = $attr.get_value(self);
            }
            @values.push(ASNValue.new(|%params));
        }
        return @values;
    }

    method serialize(--> Blob) {
        my @values = self!prepare-fields(:!for-parsing);
        my $class = Application;
        Blob.new(Serializator.serialize(0x0, @values, $class));
    }

    method parse(Blob $input --> ASNType:D) {
        my ASNValue @values = self!prepare-fields(:for-parsing);
        my $params = Parser.parse(Buf.new($input), @values);
        self.bless(|$params);
    }
}
