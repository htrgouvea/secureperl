package Zarn::AST {
    use strict;
    use warnings;
    use Getopt::Long;
    use PPI::Find;
    use PPI::Document;
    use JSON::PP;

    sub new {
        my ($class, $parameters) = @_;
        my ($file, $rules, $sarif_output);

        Getopt::Long::GetOptionsFromArray (
            $parameters,
            "file=s"  => \$file,
            "rules=s" => \$rules,
            "sarif=s" => \$sarif_output
        );

        my $self = {
            file          => $file,
            rules         => $rules,
            sarif_output  => $sarif_output,
            subset      => []
        };
        bless $self, $class;

        if ($file && $rules) {
            my $document = PPI::Document -> new($file);

            $document -> prune("PPI::Token::Pod");
            $document -> prune("PPI::Token::Comment");

            foreach my $token (@{$document -> find("PPI::Token")}) {
                foreach my $rule (@{$rules}) {
                    my @sample   = $rule -> {sample} -> @*;
                    my $category = $rule -> {category};
                    my $title    = $rule -> {name};

                    if ($self -> matches_sample($token -> content(), \@sample)) {
                        $self -> process_sample_match($document, $category, $file, $title, $token);
                    }
                }
            }
        }

        if ($sarif_output) {
            $self -> generate_sarif()
        }

        return 1;
    }

    sub matches_sample {
        my ($self, $content, $sample) = @_;

        return grep {
            my $sample_content = $_;
            scalar(grep {$content =~ m/$_/} @$sample)
        } @$sample;
    }

    sub process_sample_match {
        my ($self, $document, $category, $file, $title, $token) = @_;

        my $next_element = $token -> snext_sibling;

        # this is a draft source-to-sink function
        if (defined $next_element && ref $next_element && $next_element -> content() =~ /[\$\@\%](\w+)/) {
            # perform taint analysis
            $self -> perform_taint_analysis($document, $category, $file, $title, $next_element);
            
        }
    }

    sub perform_taint_analysis {
        my ($self, $document, $category, $file, $title, $next_element) = @_;

        my $var_token = $document -> find_first(
            sub { $_[1] -> isa("PPI::Token::Symbol") and $_[1] -> content eq "\$$1" }
        );

        if ($var_token && $var_token -> can("parent")) {
            if (($var_token->parent -> isa("PPI::Token::Operator") || $var_token -> parent -> isa("PPI::Statement::Expression"))) {
                my ($line, $rowchar) = @{$var_token -> location};
                print "[$category] - FILE:$file \t Potential: $title. \t Line: $line:$rowchar.\n";
            
            # collect the subset to generate SARIF output
            my $info = {
                category => $category,
                title    => $title,
                file     => $file,
                line     => $line,
                row      => $rowchar
            };
            push @{$self->{subset}}, $info;

            }
        }
    }

    sub generate_sarif {
        my ($self) = @_;
        my $output_file = $self -> {sarif_output};
        my $sarif_data = {
            "\$schema" => "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
            version   => "2.1.0",
            runs      => [{
                tool    => {
                    driver => {
                        name    => "ZARN",
                        version => "0.0.5"
                    }
                },
                results => []
            }]
        };

        foreach my $info (@{$self -> {subset}}) {
            my $result = {
                message => {
                    text => $info -> {title}
                },
                locations => [{
                    physicalLocation => {
                        artifactLocation => {
                            uri => $info -> {file}
                        },
                        region => {
                            startLine => $info -> {line},
                            endLine   => $info -> {row}
                        }
                    }
                }]
            };
            push @{$sarif_data -> {runs}[0]{results}}, $result;
        }

        open(my $fh, '>', $output_file) or die "Cannot open file '$output_file': $!";
        print $fh encode_json($sarif_data);
        close($fh);
    }
}

1;
