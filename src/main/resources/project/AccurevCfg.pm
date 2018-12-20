####################################################################
#
# ECSCM::Accurev::Cfg: Object definition of a perforce SCM configuration.
#
####################################################################
package ECSCM::Accurev::Cfg;
@ISA = (ECSCM::Base::Cfg);

if (!defined ECSCM::Base::Cfg) {
    require ECSCM::Base::Cfg;
}

####################################################################
# Object constructor for ECSCM::Accurev::Cfg
#
# Inputs
#   cmdr  = a previously initialized ElectricCommander handle
#   name  = a name for this configuration
####################################################################
sub new {
    my $class = shift;

    my $cmdr = shift;
    my $name = shift;

    my($self) = ECSCM::Base::Cfg->new($cmdr,"$name");
    bless ($self, $class);
    return $self;
}


## all configuration is done with accurev tool
## no command line options for user/pass/server needed

1;
