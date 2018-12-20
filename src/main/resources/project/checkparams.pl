####################################################################################
# Check Params
#
#
####################################################################################
my $dest = "$[dest]";
my $stream = "$[AccurevStreamBasis]";

if (($dest eq "") && ($stream ne ""))  {
   print "Warning: if you provided a stream ('$stream') you must provide a destiny. Please check the parameters and run the procedure again.";
} elsif (($dest ne "") && ($stream eq "") ){
   print "Warning: if you provided a destiny ('$dest') you must provide a stream. Please check the parameters and run the procedure again.";
} 
