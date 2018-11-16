enum TagClass <Universal Application Context Private>;

# OPTIONAL
role Optional {}

multi trait_mod:<is>(Attribute $attr, :$optional) is export {
    $optional does Optional;
}

# CHOICE
role Choice[:$choice-of] {
    method get-choice() { $choice-of }
}

multi trait_mod:<is>(Attribute $attr, :$choice-of!) is export {
    $attr does Choice[:$choice-of];
}

# DEFAULT
role DefaultValue[:$default-value] {
    method default-value() { $default-value }
}

multi trait_mod:<is>(Attribute $attr, :$default-value) is export {
    $attr does DefaultValue[:$default-value];
}

# SEQUENCE OF
role SequenceOf[:$sequence-of] {
    method get-sequence-type() { $sequence-of }
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
