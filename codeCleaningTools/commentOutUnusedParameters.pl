#!/usr/bin/env perl

#Just feed in build output on stdin. 
#Tested mostly with Jenkins raw build output (http://129.132.38.183:8080/job/????/consoleText).
#runs best directly in the git work tree.

#use the two first positional arguments to replace path prefixes:

$prefix = (scalar @ARGV) > 0 ? $ARGV[0] : "";
$prefixReplacement = (scalar @ARGV) > 1 ? $ARGV[1] : "";

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

while (<STDIN>){
	$line = $_;
	if($line =~/^ *Checking out Revision /){
		my ($rev, $rest) = ($line =~/^ *Checking out Revision *([[:alnum:]]+)(.*)/i);
		if($rest){
			print "Jenkins used commit '$rev'.\n";
			if($currentRev && $currentRev ne $rev){
				print STDERR "Don't use compiler warnings from a different commit ($rev (Jenkins) != $currentRev ($pwd)! The line numbers may not match.\nTip: checkout commit $rev first!\n";
				exit -1;
			}
		}
	}
	elsif($line=~/warning: unused\ parameter/) {
		my ($status, $file, $lineNr, $name) = ($line =~/^(\[ *\d*%\])? *([^:]*):(\d\d*).*warning: unused parameter ‘(\S*)’/i);
		if($file) {
			$id = "$file:$lineNr:$name";
			if($ids{$id}) { 
				print "skipping duplicate : $id\n";
				next; 
			}
			else { $ids{$id} = 1;}
			
			if(index($file, $prefix) == 0){
				$file=~ s/^\Q$prefix\E/$prefixReplacement/;
				if( -e $file ){
					$matcher = "$name\\( *\\([,)=]\\|\$\\)\\)";
					$replacement = "/* $name */";
					$ret = system("sed -n '${lineNr},/{/p' '$file' | sed -n '\\#$matcher#q1'");
					if(system("sed -n '${lineNr},/{/p' '$file' | sed -n '\\#/\\* *$name *\\*/#q1'") eq 256) {
						print "replacing '$name' : already applied.\n";
					}elsif($ret eq 256){
						print "replacing '$name'.\n";
						system("sed -i '${lineNr},/{/{s#$matcher#$replacement\\1#; t quit; b}; b; :quit; n; b quit' '$file'");
					}else{
						print STDERR "$file:$lineNr :";
						print STDERR "'WARNING: failed to replace '$name' in:";
						system("sed -n '${lineNr}p' '$file' >&2");
						print STDERR "compiler warning: $_";
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

