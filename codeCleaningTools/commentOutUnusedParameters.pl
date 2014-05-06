#!/usr/bin/env perl

use Getopt::Long;
my $force   = 0;
my $prefix = "";
my $help =  0;
my $verbose = 0;
my $debug = 0;
$result = GetOptions (
                    "prefix|p=s"   => \$prefix,
                    "replacement|r=s" => \$prefixReplacement,
                    "force|f"  => \$force,
                    "verbose|v"  => \$verbose,
                    "debug|d"  => \$debug,
                    "help|h|usage|u" => \$help
                    )
	or $help = 1;

if($help){
	print "USAGE: $ARGV[0] [(-h|--help)] | [-f|--force] [-v|--verbose] [-p|--prefix <PREFIX>] [-r|--replacement <PREFIX_REPLACEMENT>] [<INPUT_FILE>]\n";
	exit(-1);
}

#Just feed in build output on stdin. 
#Tested mostly with Jenkins raw build output (http://129.132.38.183:8080/job/????/consoleText).
#runs best directly in the git work tree.

#use the two first positional arguments to replace path prefixes:

%ids=(); 

$pwd = $ENV{'PWD'};
$currentRev = qx(git rev-parse HEAD);

if(!$currentRev) {
	print STDERR "WARNING: Could not retrieve current git revision! Please ensure manually that the code is identical to the compiled one!";
}else{
	$currentRev =~s/\s+$//;
	print "Current commit : '$currentRev'.\n";
}

$revisionOk = 0;

while (<>){
	$line = $_;
	if($line =~/^ *Checking out Revision /){
		my ($rev, $rest) = ($line =~/^ *Checking out Revision *([[:alnum:]]+)(.*)/i);
		if($rest){
			print "Jenkins used commit '$rev'.\n";
			if($currentRev && $currentRev ne $rev){
				print STDERR "Don't use compiler warnings from a different commit ($rev (Jenkins) != $currentRev ($pwd)! The line numbers may not match.\nTip: checkout commit $rev first!\n";
				if(!$force) { exit -1; }
			}
		}
	}
	elsif($line=~/warning: unused\ parameter/) {
		my ($status, $file, $lineNr, $name) = ($line =~/^(\[ *\d*%\])? *([^:]*):(\d\d*).*warning: unused parameter ‘(\S*)’/i);
		if($file) {
			$id = "$file:$lineNr:$name";
			if($ids{$id}) { 
				!$verbose or print "skipping duplicate : $id\n";
				next; 
			}
			else { $ids{$id} = 1;}
			
			if(index($file, $prefix) == 0){
				$file=~ s/^\Q$prefix\E/$prefixReplacement/;
				!$verbose or print "processing unused parameter $id in $file\n";
				
				if( -e $file ){
					$testAlreadyCmd = "sed -n '${lineNr},/{/p' '$file' | sed -n '\\#/\\* *$name *\\*/#q1; /{/q0'";
					$ret = system($testAlreadyCmd);
					!$debug or print "testing whether already applied with : $testAlreadyCmd -> $ret\n";
					if($ret eq 256) {
						print "replacing '$name' : already applied.\n";
					}else {
						$matcher = "$name\\( *\\([,)=]\\|\$\\)\\)";
						$cmd = "sed -n '${lineNr},/{/p' '$file' | sed -n '\\#$matcher#q1'";
						$ret = system($cmd);
						!$debug or print "testing whether we can replace with : $cmd -> $ret\n";
						if($ret eq 256){
							$replacement = "/* $name */";
							print "replacing '$name' with '$replacement'.\n";
							system("sed -i '${lineNr},/{/{s#$matcher#$replacement\\1#; t quit; b}; b; :quit; n; b quit' '$file'");
						}else{
							print STDERR "$file:$lineNr :";
							print STDERR "'WARNING: failed to replace '$name' in:\n";
							system("sed -n '${lineNr},/{/p' '$file' >&2");
							print STDERR "compiler warning: $_";
						}
					}
				}
				else {
					print STDERR "WARNING: could not find file '$file'.\n";
				}
			}else {
				print "ignoring '$file' - does not match prefix.\n";
			}
		}else{
			print "WARNING: could not understand : ", $_;
		}
	}
}

