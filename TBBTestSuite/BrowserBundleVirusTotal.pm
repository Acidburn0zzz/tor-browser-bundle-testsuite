package TBBTestSuite::BrowserBundleVirusTotal;

use parent 'TBBTestSuite::BrowserBundleTests';

sub description {
    'Tor Browser Bundle Virustotal checks';
}

sub type {
    'browserbundle_virustotal';
}

sub new {
    my ($ts, $testsuite) = @_;
    $testsuite->{type} = 'browserbundle_virustotal';
    $testsuite->{tests} = [
        {
            name   => 'virustotal',
            type   => 'virustotal',
            descr  => 'Analyze files on virustotal.com',
        },
    ];
    return bless $testsuite;
}

1;
