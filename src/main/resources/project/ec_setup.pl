my $projPrincipal = "project: $pluginName";
my $ecscmProj = '$[/plugins/ECSCM/project]';

if ($promoteAction eq 'promote') {
    # Register our SCM type with ECSCM
    $batch->setProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@", "AccuRev");
    
    # Give our project principal execute access to the ECSCM project
    my $xpath = $commander->getAclEntry("user", $projPrincipal,
                                        {projectName => $ecscmProj});
    if ($xpath->findvalue('//code') eq 'NoSuchAclEntry') {
        $batch->createAclEntry("user", $projPrincipal,
                               {projectName => $ecscmProj,
                                executePrivilege => "allow"});
    }
} elsif ($promoteAction eq 'demote') {
    # unregister with ECSCM
    $batch->deleteProperty("/plugins/ECSCM/project/scm_types/@PLUGIN_KEY@");
    
    # remove permissions
    my $xpath = $commander->getAclEntry("user", $projPrincipal,
                                        {projectName => $ecscmProj});
    if ($xpath->findvalue('//principalName') eq $projPrincipal) {
        $batch->deleteAclEntry("user", $projPrincipal,
                               {projectName => $ecscmProj});
    }
}

# Data that drives the create step picker registration for this plugin.
# Unregister current and past entries first.
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Accurev - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/ECSCM-Accurev - Preflight");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Accurev - Checkout");
$batch->deleteProperty("/server/ec_customEditors/pickerStep/Accurev - Preflight");

my %checkoutStep = (
    label       => "Accurev - Checkout",
    procedure   => "CheckoutCode",
    description => "Checkout code from Accurev.",
    category    => "Source Code Management"
);

my %Preflight = (
        label => "Accurev - Preflight",
        procedure => "Preflight",
        description => "Checkout code from Accurev during Preflight",
        category => "Source Code Management"
);

@::createStepPickerSteps = (\%checkoutStep,\%Preflight);
