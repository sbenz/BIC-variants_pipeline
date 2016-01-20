#!/usr/bin/perl

use strict;
use Getopt::Long qw(GetOptions);
use FindBin qw($Bin);
use File::Path qw(make_path remove_tree);
use File::Basename;

my ($input, $species, $output, $config, $help);

GetOptions ('in_maf=s' => \$input,
'species=s' => \$species,
'output=s' => \$output,
'config=s' => \$config,
'help|h' => \$help ) or exit(1);

my $uID = `/usr/bin/id -u -n`;
chomp $uID;

if(!$input || !$species || !$output || !$config ){
    die "you are missing some input";
}

my $PERL = '';
my $VCF2MAF = '';
my $HG19_FASTA = '';
my $PICARD = '';
my $JAVA = '';
my $BCFTOOLS = '';

open(CONFIG, "$config") or warn "CAN'T OPEN CONFIG FILE $config SO USING DEFAULT SETTINGS";
while(<CONFIG>){
    chomp;
    
    my @conf = split(/\s+/, $_);
    if($conf[0] =~ /perl/i){
        if(!-e "$conf[1]/perl"){
            die "CAN'T FIND perl IN $conf[1] $!";
        }
        $PERL = $conf[1];
    }
    elsif($conf[0] =~/vcf2maf/i){
        if(!-e "$conf[1]/maf2maf.pl"){
            die "CAN'T FIND maf2maf.pl in $conf[1] $!";
        }
        $VCF2MAF = $conf[1];
    }
    elsif($conf[0] =~/bcftools/i){
        if(!-e "$conf[1]/bcftools"){
            die "CAN'T FIND bcftools in $conf[1] $!";
        }
        $BCFTOOLS = $conf[1];
    }
    elsif($conf[0] =~ /samtools/i){
        if(!-e "$conf[1]/samtools"){
            die "CAN'T FIND samtools IN $conf[1] $!";
        }
        my $path_tmp = $ENV{'PATH'};
        $ENV{'PATH'} = "$conf[1]:$path_tmp";
    }
    elsif($conf[0] =~ /tabix/i){
        if(!-e "$conf[1]/tabix"){
            die "CAN'T FIND tabix IN $conf[1] $!";
        }
        my $path_tmp = $ENV{'PATH'};
        $ENV{'PATH'} = "$conf[1]:$path_tmp";
    }
    elsif($conf[0] =~ /hg19_fasta/i){
        if(!-e "$conf[1]"){
            die "CAN'T FIND $conf[1] $!";
        }
        $HG19_FASTA = $conf[1];
    }
    elsif($conf[0] =~ /picard/i){
        if(!-e "$conf[1]/picard.jar"){
            die "CAN'T FIND picard.jar IN $conf[1] $!";
        }
        $PICARD = $conf[1];
    }
    elsif($conf[0] =~ /java/i){
        if(!-e "$conf[1]/java"){
            die "CAN'T FIND java IN $conf[1] $!";
        }
        $JAVA = $conf[1];
        my $path_tmp = $ENV{'PATH'};
        $ENV{'PATH'} = "$conf[1]:$path_tmp";
    }
}
close CONFIG;

## FOR RIGHT NOW, ONLY HG19 IS BEING USED

my $REF_FASTA = $HG19_FASTA;
my $REF_DICT= $REF_FASTA;
$REF_DICT =~ s/\.[^.]+$//;
$REF_DICT = "$REF_DICT.dict";

# die if vcf2maf is empty, VEP, etc.
if(!-e $VCF2MAF ) {
    die "Cannot find vcf2maf. Either add or correct config file. $!";
}
if(!-e $PERL) {
    die "Need PERL specified in config. $!";
}

my $ref_base = basename($REF_FASTA);
# softlink reference
if(!-e "$output/ref"){
    mkdir("$output/ref", 0755) or die "Making ref didn't work $!";
}
if(!-e "$output/ref/$ref_base"){
    symlink($REF_FASTA, "$output/ref/$ref_base");
    symlink("$REF_FASTA.fai", "$output/ref/$ref_base.fai");
}
my $refDictBase = basename($REF_DICT);
if (!-e "$output/ref/$refDictBase"){
    symlink($REF_DICT, "$output/ref/$refDictBase");
}

if( ! -d "$output/xtra/" ){
    print "$output/xtra/ does not exist. Will create it now\n";
    mkdir("$output/xtra", 0755) or die "Making tmp didn't work $!";
}
else{
    remove_tree("$output/xtra") or die "Not able to remove directory $!";
    mkdir("$output/xtra", 0755) or die "Making tmp didn't work $!";
}

# To make simple vcf, first use the maf2vcf.pl from cyriac...
`/opt/common/CentOS_6/bin/v1/perl $VCF2MAF/maf2vcf.pl --input-maf $input --ref-fasta $output/ref/$ref_base --output-dir $output/xtra`;
#`echo "##fileformat=VCFv4.2" > $output/xtra/simpleVCF.vcf; echo "#CHROM POS ID REF ALT QUAL FILTER INFO" | tr ' ' '\t' >> $output/xtra/simpleVCF.vcf`;

#open(my $out_fh, ">", "$output/xtra/simpleVCF.vcf");
#print $out_fh "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n";

my @files = glob("$output/xtra/*.vcf");
foreach my $file (@files) {
    if("$file" ne "$output/xtra/simpleVCF.vcf"){
        print "$file\n";
        #`grep -v '^#' $file | awk ' {print $1'\t'$2'\t'$3't'$4't'$5'\t.\t.\t.'}' >>  $output/xtra/simpleVCF.vcf`;
        open(my $outCurr , ">", "$file\_stripped.vcf");
        open(my $curr_file, "<", $file);
        print $outCurr "##fileformat=VCFv4.2\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n";
        my @lines = <$curr_file>;
        foreach my $line (@lines){
            next if ($line =~ m/^#/);
            my @splitLines = split("\t", $line);
            my $outLine = join("\t", @splitLines[0 .. 5]); 
            print $outCurr "$outLine\t.\t.\n";
        }
        close $outCurr;
        close $curr_file ;
    }
}
#close $out_fh ;

# Then I want to sort the vcf.

my $strippedFiles = join(" INPUT=", glob("$output/xtra/*.vcf_stripped.vcf"));

`$JAVA/java -Djava.io.tmpdir=/scratch/$uID -jar $PICARD/picard.jar SortVcf VALIDATION_STRINGENCY=LENIENT INPUT=$strippedFiles  OUTPUT=$output/xtra/sortedSimpleVCF.vcf SEQUENCE_DICTIONARY=$output/ref/$refDictBase`;

`sed 's/chr//g;s/ID=chr/ID=/g' $output/xtra/sortedSimpleVCF.vcf | uniq > tmp; mv tmp $output/xtra/sortedSimpleVCF.vcf`;

# BGZIP, tabix stuff:
`bgzip -f $output/xtra/sortedSimpleVCF.vcf`;
`tabix -p vcf $output/xtra/sortedSimpleVCF.vcf.gz`;

`$BCFTOOLS/bcftools annotate --annotations $Bin/../data/ExAC.r0.3.sites.pass.minus_somatic.vcf.gz --columns AC,AN,AF --output-type v --output $output/xtra/exac.vcf $output/xtra/sortedSimpleVCF.vcf.gz`;

## for right now, just move the vcf to the main output. LATER, I will add to this script to give an intermediate file.
`mv $output/xtra/exac.vcf $output/exact.vcf`;