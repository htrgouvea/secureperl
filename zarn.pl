#!/usr/bin/env perl

use 5.030;
use strict;
use warnings;
use Carp;
use lib "./lib/";
use Getopt::Long;
use Zarn::AST;
use Zarn::Files;
use Zarn::Rules;
use Zarn::Sarif;
use JSON;

our $VERSION = '0.0.9';

sub main {
    my $rules = "rules/default.yml";
    my ($source, $ignore, $sarif, @results);

    Getopt::Long::GetOptions (
        "r|rules=s"   => \$rules,
        "s|source=s"  => \$source,
        "i|ignore=s"  => \$ignore,
        "srf|sarif=s" => \$sarif
    );

    if (!$source) {
        print "\nZarn v0.0.9"
        . "\nCore Commands"
        . "\n==============\n"
        . "\tCommand          Description\n"
        . "\t-------          -----------\n"
        . "\t-s, --source     Configure a source directory to do static analysis\n"
        . "\t-r, --rules      Define YAML file with rules\n"
        . "\t-i, --ignore     Define a file or directory to ignore\n"
        . "\t-srf, --sarif    Define the SARIF output file\n"
        . "\t-h, --help       To see help menu of a module\n\n";

        exit 1;
    }

    my @rules = Zarn::Rules -> new($rules);
    my @files = Zarn::Files -> new($source, $ignore);

    foreach my $file (@files) {
        if (@rules) {
            my @analysis = Zarn::AST -> new ([
                "--file" => $file,
                "--rules" => @rules
            ]);

            push @results, @analysis;
        }
    }

    foreach my $result (@results) {
        my $category       = $result -> {category};
        my $file           = $result -> {file};
        my $title          = $result -> {title};
        my $line_sink      = $result -> {line_sink};
        my $rowchar_sink   = $result -> {rowchar_sink};
        my $line_source    = $result -> {line_source};
        my $rowchar_source = $result -> {rowchar_source};

        print "[$category] - FILE:$file \t Potential: $title. \t Dangerous function on line: $line_sink:$rowchar_sink \t Data point possibility controlled: $line_source:$rowchar_source\n";
    }

    if ($sarif) {
        my $sarif_data = Zarn::Sarif -> new (@results);

        open(my $output, '>', $sarif) or croak "Cannot open file '$sarif': $!";
        
        print $output encode_json($sarif_data);
        
        close($output);
    }

    return 0;
}

exit main();