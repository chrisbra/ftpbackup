sub parse_config {
    my ($self, $file) = @_;
    open(my $fh, $file) || die "open($file): $!";
    my @lines = <$fh>;
    close $fh;
    chomp(@lines);
    my $config = $self->{config} = {};
    my $section;
    for (@lines) {
        s/^\s*//;
        s/\s*$//;
        next unless /\S/;
        next if /^#/;
        if (/^ \[ (.*) \] $/x) {
            $section = $config->{uc$1} = {};
        }
        elsif (/^ (\w+) \s* = \s* (.*) $/x) {
            die "key=value pair outside of a section" unless $section;
            $section->{lc$1} = $2;
        }
        else {
            die "invalid line in $file: $_";
        }
    }
}
