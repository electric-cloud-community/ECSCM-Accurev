@files = (
    ['//property[propertyName="ECSCM::Accurev::Cfg"]/value', 'AccurevCfg.pm'],
    ['//property[propertyName="ECSCM::Accurev::Driver"]/value', 'AccurevDriver.pm'],
    ['//property[propertyName="checkout"]/value', 'accurevCheckoutForm.xml'],
    ['//property[propertyName="preflight"]/value', 'accurevPreflightForm.xml'],
    ['//property[propertyName="sentry"]/value', 'accurevSentryForm.xml'],
    ['//property[propertyName="trigger"]/value', 'accurevTriggerForm.xml'],
    ['//property[propertyName="createConfig"]/value', 'accurevCreateConfigForm.xml'],
    ['//property[propertyName="editConfig"]/value', 'accurevEditConfigForm.xml'],
    ['//property[propertyName="ec_setup"]/value', 'ec_setup.pl'],
    ['//procedure[procedureName="CheckoutCode"]/step[stepName="checkParams"]/command' , 'checkparams.pl'],
    ['//procedure[procedureName="CheckoutCode"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'accurevCheckoutForm.xml'],
    ['//procedure[procedureName="Preflight"]/propertySheet/property[propertyName="ec_parameterForm"]/value', 'accurevPreflightForm.xml'],
);
