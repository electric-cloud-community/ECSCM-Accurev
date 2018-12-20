####################################################################
#
# ECSCM::Accurev::Driver  Object to represent interactions with 
#        perforce.
####################################################################
package ECSCM::Accurev::Driver;
@ISA = (ECSCM::Base::Driver);
use ElectricCommander;
use Time::Local;
use Getopt::Long;

my $pluginName = q{@PLUGIN_NAME@};

if (!defined ECSCM::Base::Driver) {
    require ECSCM::Base::Driver;
}

if (!defined ECSCM::Accurev::Cfg) {
    require ECSCM::Accurev::Cfg;
}

# get SIMPLE XML from the plugin directory
if ("$ENV{COMMANDER_PLUGIN_PERL}" ne "") {
    # during tests
    push @INC, "$ENV{COMMANDER_PLUGIN_PERL}";
} else {
    # during production
    push @INC, "$ENV{COMMANDER_PLUGINS}/$pluginName/agent/perl";   
}

require XML::Simple;

####################################################################
# Object constructor for ECSCM::Accurev::Driver
#
# Inputs
#    cmdr          previously initialized ElectricCommander handle
#    name          name of this configuration
#                 
####################################################################
sub new {
    my $this = shift;
    my $class = ref($this) || $this;

    my $cmdr = shift;
    my $name = shift;

    my $cfg = new ECSCM::Accurev::Cfg($cmdr, "$name");
    if ("$name" ne "" ) {
        my $sys = $cfg->getSCMPluginName();
        if ("$sys" ne "ECSCM-Accurev") { die "SCM config $name is not type ECSCM-Accurev"; }
    }
    my ($self) = new ECSCM::Base::Driver($cmdr,$cfg);

    bless ($self, $class);
    return $self;
}

####################################################################
# isImplemented
####################################################################
sub isImplemented {
    my ($self, $method) = @_;
    
    if ($method eq 'getSCMTag' || 
        $method eq 'checkoutCode' || 
        $method eq 'apf_driver' || 
        $method eq 'cpf_driver') {
        return 1;
    } else {
        return 0;
    }
}


####################################################################
# helper utilties
####################################################################
#------------------------------------------------------------------------------
# accurev
#
#       Log in to accurev then run the supplied command.
#------------------------------------------------------------------------------
sub accurev
{
    my ($self,$command, $opts) = @_;

    # Have to be logged in to use the majority of Accurev commands.
    # Always login before issuing an accurev command as we want the command
    # to be issued as this user and the same user could have issued a logout
    # while this script is running.  There is no harm in issuing multiple 
    # login commands, the session file should just keep getting updated.

    # Should we be checking the user's home directory for the existence of
    # a session file?

    # Set the base Accurev login command
    print "Logging into Accurev as $opts->{scm_user}\n";
    my $loginCommand = "accurev login $opts->{scm_user} ";

    # Add the password
    my $passwordStart = 0;
    my $passwordLength = length($opts->{scm_password});
    if ($passwordLength) {
        
        $passwordStart = length($loginCommand);
        $loginCommand .= $opts->{scm_password};
    }
    else {
        # Add a pair of double quotes if no password
        $loginCommand .= '""';
    }
        
    $self->RunCommand($loginCommand,
            {LogCommand => 1, HidePassword => 1, 
             passwordStart => $passwordStart, 
             passwordLength =>$passwordLength});

    #The command can be null in case we just want to login
    if ($command ne undef){
        print "Running Accurev command \"$command\" \n";
        return $self->RunCommand("accurev $command", {LogCommand=>1});
    } else {
    return 1;
    }
}



####################################################################
# checkoutCode for ecsnapshot
####################################################################

sub checkoutCode()
{
    my ($self, $opts) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
            $opts->{$k}=$row{$k};
    }
    
    if (!defined $opts->{dest} ) {
        print "No destination argument\n";
        return undef;
    }
    if (!defined $opts->{AccurevStreamBasis}) {
        print "No AccurevStrameBasis argument\n";
        return undef;
    }
    print "Credential=$opts->{credential}\n";
    
    # Load userName and password from the credential
    ($opts->{scm_user}, $opts->{scm_password}) =
      $self->retrieveUserCredential($opts->{credential}, $opts->{scm_user}, $opts->{scm_password});

    if (!defined $opts->{scm_user} || "$opts->{scm_user}" eq "" ) {
        print "No user specified\n";
        return undef;
    }
    if (!mkdir $opts->{dest}, 0777 ) {
        print "can't mkdir $opts->{dest}: $!\n";
    }
    
    if ($opts->{AccurevUseModTime} eq 1) {
        $ENV{ACCUREV_USE_MOD_TIME} = 1;
    } 
    
    my $command ="";
    if (($opts->{dest} ne "") && ($opts->{AccurevStreamBasis} ne "")) {
        $command = "pop -R -v \"$opts->{AccurevStreamBasis}\" -L  \"$opts->{dest}\" .";
    } else {
        $command = "pop -R .";
    }
    
    #checkout the code    
    my $result = $self->accurev($command, $opts);
    
    my $start = "";

    if ($opts->{lastSnapshot} && $opts->{lastSnapshot} ne "") {
        # use the lastSnapshot that was passed in.
        # note: don't include
        # the change given by $::gLastSnapshot, since that was already
        # included in the previous build.
        $opts->{lastSnapshot}++;
        $start = $opts->{lastSnapshot};
    } else {
        $start = $self->getStartForChangeLog($scmKey);
    }


    #get the changes
    my $changed_cmd = "hist -t now -s $opts->{AccurevStreamBasis}";
    my $changes = $self->accurev($changed_cmd, $opts);
    
    my $scmKey = "Accurev";
    
    $self->setPropertiesOnJob($scmKey, "1234565", $changes);
    
    
    if (defined $opts->{updatesFile} && $opts->{updatesFile} ne "") {
        $self->writeUpdates($command, $changes, $opts->{updatesFile});
    }    
    
    return 1;
}

#-------------------------------------------------------------------------
# writeUpdates
#
#      Given a list of Perforce changes, create a file describing the
#      corresponding updates in more detail.
#
# Results:
#      None.
#
# Side Effects:
#      A file is written containing one section for each line in
#      $changes.  This section contains the name of the user making
#      the change, and the details for the change provided by Perforce.
#
# Arguments:
#      p4Command -     The root p4 command
#      changes -       Output from "p4 changes", listing one change number
#                      on each line.
#      fileName -      Name of file in which to write the details.
#-------------------------------------------------------------------------

sub writeUpdates {
    my ($self, $p4Command, $changes, $fileName) = @_;
    print "Writing update log to $fileName\n";
    open (UPDATELOG, "> $fileName") || die "error: can't "
            . "open updates file \"$fileName\": $!";
    my @lines = split(/\n/, $changes);
    my $prefix = "";
    while (defined(my $line = shift(@lines))) {
        if ($line =~ /^Change (\d+) [^@]*by ([^@]+)@/) {
            my $change = $1;
            my $user = $2;
            my $desc = $self->RunCommand("$p4Command describe -s $change", 
                    {LogCommand => 1});
            print(UPDATELOG $prefix . "-" x 25 . " " . $user . " " .
                "-" x 25 . "\n\n" . $desc );
            $prefix = "\n";
        }
    }
    close(UPDATELOG) || die "error: error "
            . "closing updates file \"$fileName\": $!";
}


####################################################################
# get scm tag for sentry (continuous integration)
####################################################################


####################################################################
# getSCMTag
# 
# Get the latest changelist on this branch/client
#
# Args:
# Return: 
#    changeNumber - a string representing the last change sequence #
#    changeTime   - a time stamp representing the time of last change     
####################################################################
sub getSCMTag {
    my ($self, $opts) = @_;

    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
            $opts->{$k}=$row{$k};
    }

    # Get the config on the trigger schedule
    my $accurevStream = $opts->{AccurevStream};

    if (length ($accurevStream) == 0) {
        $self->issueWarningMsg ("*** No AccuRev stream was specified\n");
        return (undef,undef);
    }

    # Load userName and password from the credential
    ($opts->{scm_user}, $opts->{scm_password}) =
      $self->retrieveUserCredential($opts->{credential}, $opts->{scm_user}, $opts->{scm_password});
    
    #login into accurev	
    $self->accurev(undef, $opts);

    my $temp_stream = $accurevStream; 
    my $depot_name, $parent, $type, $name;

    my ($transactionNumber, $changeTimestamp) = $self->run_accu_hist($accurevStream);

    do {      
        my $hierarchy_sentry_cmd = "accurev show -fx -s \"$temp_stream\" streams";
        my $output =  $self->RunCommand($hierarchy_sentry_cmd, 
                                            {LogCommand => 1, LogResult => 1});

        $xml = new XML::Simple;
        $data = $xml->parse_string($output);

        $name = $data->{stream}->{'name'};
        $depot_name = $data->{stream}->{'depotName'};
        $type = $data->{stream}->{'type'};
        $parent = $data->{stream}->{'basis'};
        
        #print "name $name depot name $depot_name type $type parent $parent \n";

        my ($temp_tn, $temp_ts) = $self->run_accu_hist($parent) if ($parent ne '');

        #check the newer date
        if ($temp_ts gt $changeTimestamp){ 
            $changeTimestamp = $temp_ts;
            $transactionNumber = $temp_tn;
        }

        $temp_stream = $parent if ($parent ne '');
        
    } while ((($type ne "snapshot") && ($depot_name ne $name) && ($parent ne '')));


    return ($transactionNumber, $changeTimestamp);
}

sub run_accu_hist{
        my ($self, $accurevStream) = @_;
        # set the AccuRev command
        #     accurev hist -s IntQA -t highest
        #     transaction 137869; promote; 2007/10/01 07:37:26 ; user: abcdef
        my $command = "accurev hist -t highest";
        $command .= ' -s "' . $accurevStream .'"' if (length ($accurevStream) > 0);

        # run AccuRev
        my $cmndReturn =  $self->RunCommand($command, 
                                            {LogCommand => 1, LogResult => 1});
        
        $cmndReturn =~ /^\s*transaction (\d+);.*; (.*?) ;/;

        $transactionNumber = $1;
        $transactionTimeString = $2;
        $changeTimestamp=undef;
        
        if (length $transactionTimeString > 0) {
            # Get the timestamp for the revision (local time)
            #     2007/10/01 07:37:26
            $transactionTimeString =~ '(....)/(..)/(..) (..):(..):(..)';
            #                                sec min hr  day mon   yr
            $changeTimestamp =  timelocal($6, $5, $4, $3, $2-1, $1-1900);
        }
        
        return ($transactionNumber, $changeTimestamp);
}

####################################################################
# agent preflight file
####################################################################

#------------------------------------------------------------------------------
# getScmInfo
#
#       If the client script passed some SCM-specific information, then it is
#       collected here.
#       For accurev, get the following:
#       1) stream name
#       2) user name
#       3) password
#------------------------------------------------------------------------------
sub apf_getScmInfo()
{
    my ($self, $opts) = @_;
    
    my $scmInfo = $self->pf_readFile("ecpreflight_data/scmInfo");

    if ($scmInfo =~ m/(.*)\n(.*)\n(.*)\n/ ) {
        #print "accurev password defined, so grabbing it\n";
        $opts->{AccurevStreamBasis} = $1;
        $opts->{scm_user} = $2;
        $opts->{scm_password} = $3;
        
    }  elsif ($scmInfo =~ m/(.*)\n(.*)\n/ ) {
        $opts->{AccurevStreamBasis} = $1;
        $opts->{scm_user} = $2;
    }
    print("Accurev information received from client:\n"
          . "Accurev Stream Basis: $opts->{AccurevStreamBasis}\n"
          . "Accurev User: $opts->{scm_user}\n");
    print("Accurev Password: ****\n") if (length $opts->{scm_password});
    print("\n");


}

#------------------------------------------------------------------------------
# createSnapshot
#
#       Create a snapshot before overlaying the deltas passed
#       from the client.
#------------------------------------------------------------------------------

sub apf_createSnapshot()
{
    my ($self, $opts) = @_;
    
    return $self->checkoutCode($opts);
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------

sub apf_driver()
{   
    my ($self, $opts) = @_;
    
    # add configuration that is stored for this config
    my $name = $self->getCfg()->getName();
    my %row = $self->getCfg()->getRow($name);
    foreach my $k (keys %row) {
            $opts->{$k}=$row{$k};
    }

    if ($opts->{test}) { $self->setTestMode(1); }
    $opts->{delta} = "ecpreflight_files";
    $self->apf_downloadFiles($opts);
    $self->apf_transmitTargetInfo($opts);
    $self->apf_getScmInfo($opts);
    $self->apf_createSnapshot($opts);
    $self->apf_deleteFiles($opts);
    $self->apf_createDirectories($opts);
    $self->apf_overlayDeltas($opts);
}

####################################################################
# client preflight file
####################################################################

#------------------------------------------------------------------------------
# accurev
#
#       Log in to accurev then run an accurev command.  Also used for testing, 
#       where the requests and responses may be pre-arranged.
#------------------------------------------------------------------------------
sub cpf_accurev {
    my ($self,$opts,$command, $properties) = @_;

    # Have to be logged in to use the majority of Accurev commands.
    # Always login before issuing an accurev command as we want the command
    # to be issued as this user and the same user could have issued a logout
    # while this script is running.  There is no harm in issuing multiple 
    # login commands, the session file should just keep getting updated.

    # Should we be checking the user's home directory for the existence of
    # a session file?

    if (!$opts->{opt_Testing}) {
        $self->cpf_debug("Logging into Accurev");
        if (!defined($opts->{scm_password}) || $opts->{scm_password} eq "") {
            $self->RunCommand("accurev login $opts->{scm_user} \"\" ");
        } else {
            $self->RunCommand("accurev login $opts->{scm_user} $opts->{scm_password} ");
        }
    }

    $self->cpf_debug("Running Accurev command \"$command\"");

    if ($opts->{opt_Testing}) {
        my $request = uc("accurev_$command");
        $request =~ s/[^\w]//g;
        if (defined($ENV{$request})) {
            return $ENV{$request};
        } else {
            $self->cpf_error("Pre-arranged command output not found in ENV");
        }
    } else {
        my $result =  $self->RunCommand("accurev $command", $properties);
        $self->cpf_debug("result=\n$result");
        return $result;
    }
}

#------------------------------------------------------------------------------
# checkElements
#
#       Check elements in workspace for any kept and/or modified elements,
#       depending on $opts->{AccurevStatOption}.  Error out if no elements returned
#       or if there are overlap or underlap elements.
#------------------------------------------------------------------------------
sub cpf_checkElements
{
    my ($self,$opts) = @_;
    # Collect a list of files.
    $opts->{AccurevFiles} = $self->cpf_accurev($opts,"stat -fn $opts->{AccurevStatOption}");

    if (!$opts->{AccurevFiles} || $opts->{AccurevFiles} eq "") {
        if ($opts->{scm_pending}) {
            $self->cpf_error("No pending files found in $opts->{scm_path}");
        } else {
            $self->cpf_error("No kept files found in $opts->{scm_path}");
        }
    }

    # The presence of strings (overlap) or (underlap) in the output likely
    # means at least one element has this status.  Can make a more strict check.

    if ($opts->{AccurevFiles} =~m/(overlap)/ || $opts->{AccurevFiles} =~m/(underlap)/ ) {
            $self->cpf_error("Files found in $opts->{scm_path} with overlap or underlap status.\n"  
                . "Workspace should be updated and conflicts resolved before attempting preflight.");
    }
}

#------------------------------------------------------------------------------
# copyDeltas
#
#       Finds kept or pending files, and calls putFiles to upload them
#       to the server.
#------------------------------------------------------------------------------
sub cpf_copyDeltas()
{
    my ($self,$opts) = @_;
    $self->cpf_display("Collecting delta information");

    # In order to create a workspace, need to be logged in, so save username
    # and password.  The password will be preserved in clear text in a file on the
    # file system.  This could be problematic.  Maybe need to rely on some
    # accurev default user that doesn't have a password, or has a generic 
    # password.
    
    if (!defined($opts->{scm_password}) || $opts->{scm_password} eq "") {
        $self->cpf_saveScmInfo($opts,"$opts->{AccurevStreamBasis}\n"
                    . "$opts->{scm_user}\n" );
        
    } else {
        $self->cpf_saveScmInfo($opts,"$opts->{AccurevStreamBasis}\n"
            . "$opts->{scm_user}\n"
            . "$opts->{scm_password}\n" );
        
    }

    $self->cpf_findTargetDirectory($opts);
    $self->cpf_createManifestFiles($opts);
    my $count = 0;
    my $source = "";
    my $dest = "";
    my $type = "";

    # Parse $opts->{AccurevFiles}.
    # every 2 lines of $opts->{AccurevFiles} comprises the state of one element.
    # if the element is kept, example output is:
    #./installerTestScripts/electriccloud/electriccommander/file with space.sh
    #depot2_build/1 (2/1) (kept) (member)
    # 
    # if the element is modified but not kept, example output is:
    #./installerTestScripts/test.sh
    #depot2/4 (29/3) (modified)

    # go line by line, even lines are the element name, odd lines are the state.
    foreach(split/\n/, $opts->{AccurevFiles}) {
        
        my $elem = $_;
        if ($count % 2) {
            # this line contains information about the element
            if ($elem =~ m/\s\(modified\)$/) {
                $type = "(modified)";
            } else {
                $elem =~ m/$opts->{AccurevClient}(\S*)\s+(\S+)\s+(\S+)/; 
                $type = $3;
            }
            # depending on whether the element is a file or directory, and on its 
            # type, call the appropriate function.
            if ($type ne "(defunct)") {
                if (-d $source) {
                $self->cpf_addDirectory($dest);
                } else {
                    $self->cpf_addDelta($opts,$source, $dest);
                }
            } else {
                $self->cpf_addDelete($dest);
            }

            $source = "";
            $dest = "";
            $type = "";

        } else {
            # this line is the file or directory name
            $source = $elem;
            # remove any leading or trailing spaces
            $source =~ s/(^\s+|\s+$)//g;
            
            # replace all \ with /
            $source =~ s/\\/\//g;
            # if the source start with ./, remove it
            $source =~ s/.\///;
            $dest = $source;
            $source = File::Spec->catfile($opts->{scm_path}, $source );
            # replace all \ with / after catfile call
            $source =~ s/\\/\//g;
        }
        $count = $count +1;
    }
    
    $self->cpf_closeManifestFiles($opts);
    $self->cpf_uploadFiles($opts);
    
}

#------------------------------------------------------------------------------
# autoCommit
#
#       Automatically commit changes in the user's client.  Error out if:
#       - A check-in has occurred since the preflight was started, and the
#         policy is set to die on any check-in.
#       - A check-in has occurred and the previously saved list of
#         files is different than the current list of kept files
#------------------------------------------------------------------------------
sub cpf_autoCommit()
{
    my ($self,$opts) = @_;
    # Make sure none of the files have been touched since the build started.

    $self->cpf_checkTimestamps($opts);

    # get the current list of files
    my $statOutput = $self->cpf_accurev($opts,"stat -fn $opts->{AccurevStatOption}");

    # Compare it with the previously preserved list of files.
    # File overlaps will be caught here.
    if ($statOutput ne $opts->{AccurevFiles}) {
        $self->cpf_error("Files have been added and/or removed from the default group"
                . " since the preflight build was launched");
    }
 
    # do update udpate preview here to see if there have been checkins
    my $updateIOutput = $self->cpf_accurev($opts,"update -i");

    if ($updateIOutput =~m/Would make \d+ change/) {
        if ($opts->{opt_DieOnNewCheckins}) {
            $self->cpf_error("A check-in has been made since ecpreflight was started. "
                    . "Update and resolve conflicts, then retry the preflight "
                    . "build");
        }
    }

    # Commit the files.  Use the commit description.

    $self->cpf_display("Promoting changes");
    my $output = "";
    if ($opts->{scm_pending}) {
        # -K option keeps all modified files before promoting them
        # with the rest of the kept files
        $output = $self->cpf_accurev($opts,"promote -pK -c \"$opts->{scm_commitComment}\" ");
    } else {
        # -k option promotes all kept files
        $output = $self->cpf_accurev($opts,"promote -k -c \"$opts->{scm_commitComment}\" ");
    }

    $self->cpf_display("$output");
    $self->cpf_display("Changes have been successfully promoted");
}

#------------------------------------------------------------------------------
# driver
#
#       Main program for the application.
#------------------------------------------------------------------------------
sub cpf_driver()
{
    my ($self,$opts) = @_;
    $self->cpf_display("Executing Accurev actions for ecpreflight");

    $::gHelpMessage .= "
Accurev Options:
  --accurevuser <user>      The value of ACCUREVUSER.  May also be set in the
                            environment.  Defaults to the Commander user if
                            not specified.
  --accurevpasswd <password>The value of ACCUREVPASSWD.  May also be set in the
                            environment.
  --accurevpath <path>      The value of ACCUREVPATH.  May also be set in the
                            environment.  This is a required value.
  --accurevpending          Use this option to have the client workspace scanned
                            for all pending elements using the \"stat -fn -p\" 
                            command.  By default, the workspace is scanned for 
                            all kept elements using the \"stat -fn -k\" command.
";

    my %ScmOptions = ( 
        "accurevuser=s"        => \$opts->{scm_user},
        "accurevpasswd=s"      => \$opts->{scm_password},
        "accurevpath=s"        => \$opts->{scm_path},
        "accurevpending"       => \$opts->{scm_pending},
    );


    Getopt::Long::Configure("default");
    if (!GetOptions(%ScmOptions)) {
        error($::gHelpMessage);
    }    

    if ($::gHelp eq "1") {
        $self->cpf_display($::gHelpMessage);
        return;
    }    

    $opts->{AccurevStatOption} = "-k";
    $opts->{delta} = "ecpreflight_files";
    # Get values for SCM-specific options passed on the command-line.


    # Collect SCM-specific information from the configuration 
    $self->extractOption($opts, "scm_user", { env => "ACCUREVUSER" });
    $self->cpf_debug("accurev user: $opts->{scm_user}");

    $self->extractOption($opts, "scm_password", { env => "ACCUREVPASSWD" });
    if (defined($opts->{scm_password})) {
        $self->cpf_debug("accurev password is defined");
    }
 
    $self->extractOption($opts,"scm_path", { required => 1, env => "ACCUREVPATH" });
    $self->cpf_debug("accurev path: $opts->{scm_path}");

    $self->extractOption($opts,"scm_pending", { required => 0, env => "ACCUREVCHECKPENDING" });

    if ($opts->{scm_pending}) {
        $opts->{AccurevStatOption} = "-p";
        $self->cpf_display("Workspace will be scanned for all pending elements");
    } else {
        $self->cpf_display("Workspace will be scanned for all kept elements");
    }

    # If the preflight is set to auto-commit, require a commit comment.

    if ($opts->{scm_autoCommit} &&
            (!defined($opts->{scm_commitComment})|| $opts->{scm_commitComment} eq "")) {
        $self->cpf_error("Required element \"scm/commitComment\" is empty or absent in "
                . "the provided options.  May also be passed on the command "
                . "line using --commitComment");
    }

    chdir "$opts->{scm_path}";
        
    # command: accurev info
    my $infoOutput = $self->cpf_accurev($opts,"info");
    
    foreach(split/\n/, $infoOutput) {        
        if ($_ =~ m/Basis:\s+(\S*)/) {
            $opts->{AccurevStreamBasis} = $1;
        }
        
        # get client name here as well
        if ($_ =~ m/Workspace\/ref:\s+(\S*)/) {
            $opts->{AccurevClient} = $1;
        }
    }

    if(!$opts->{AccurevStreamBasis}) {
        $self->cpf_error("Unable to determine the Basis for workspace located in: $opts->{scm_path}");
    }

    $self->cpf_debug("accurev stream basis: " . $opts->{AccurevStreamBasis});

    if(!$opts->{AccurevClient}) {
        $self->cpf_error("Unable to determine the client name for workspace located in: $opts->{scm_path}");
    }

    $self->cpf_debug("accurev client: " . $opts->{AccurevClient});

    $self->cpf_checkElements($opts);

    # Copy the deltas to a specific location.

    $self->cpf_copyDeltas($opts);

    if ($opts->{scm_autoCommit}) {
        if (!$opts->{opt_Testing}) {
            $self->cpf_waitForJob($opts);
        }
        $self->cpf_autoCommit($opts);
    }
}

####################################################################
# updateLastGoodAndLastCompleted
#
# Side Effects:
#   If the current job outcome is "success" copy the current
#   revision from the job level property to the "lastGood"
#   property and the "lastCompleted" property.  If not success,
#   only copy the current revision to the "lastCompleted" property.
#
# Arguments:
#   self -              the object reference
#   opts -              A reference to the hash with values
#
# Returns:
#   nothing.
#
####################################################################
sub updateLastGoodAndLastCompleted
{
    my ($self, $opts) = @_;

    my $prop = "/myJob/outcome";

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperty", $prop);

    if ($success) {

    my $grandParentStepId = "";
    $grandParentStepId = $self->getGrandParentStepId();
    
    if (!$grandParentStepId || $grandParentStepId eq "") {
        # log that we couldn't get the grand parent step id
        return;
    }

    my $properties = $self->getPropertyNamesAndValuesFromPropertySheet("/myJob/ecscm_snapshots");

    foreach my $key ( keys % {$properties}) {
        my $snapshot = $properties->{$key}; 
        
        if ("$snapshot" ne "") { 
    
        $prop = "/myProcedure/ecscm_snapshots/$key/lastCompleted";
        $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", "$prop", "$snapshot", {jobStepId => $grandParentStepId});

        my $val = "";
        $val = $xpath->findvalue('//value')->value();

    if ($val eq "success") {
            $prop = "/myProcedure/ecscm_snapshots/$key/lastGood";
            $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "setProperty", "$prop", "$snapshot", {jobStepId => $grandParentStepId});            
        }

        } else {
        # log that we couldn't get the job revision
        }
    }

    } else {
    # log the error code and msg
    }
}

####################################################################
# getPropertyNamesAndValuesFromPropertySheet
#
# Side Effects:
#   Extracts propertyNames and values from the specified property sheet.
#
# Arguments:
#   self -              the object reference
#   propertySheet -     the property sheet to parse
#
# Returns:
#   A reference to a hash of propertyNames and values.
####################################################################
sub getPropertyNamesAndValuesFromPropertySheet
{
    my ($self, $propertySheet) = @_;

    my %properties = {};

    my ($success, $xpath, $msg) = $self->InvokeCommander({SuppressLog=>1,IgnoreError=>1}, "getProperties", {recurse => "1", path => "$propertySheet"});

    if ($success) {

    my $results = $xpath->find('//property');
    if (!$results->isa('XML::XPath::NodeSet')) {
                # log that we didn't get a nodeset
           }
           foreach my $context ($results->get_nodelist) {
                my $name = $xpath->find('./propertyName', $context);
                my $value = $xpath->find('./value', $context);
        $properties{$name} = $value;
           }

    } else {
    # log the error code and msg
    }

    return \%properties;
}

1;
