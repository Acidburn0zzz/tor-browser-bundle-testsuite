package TBBTestSuite::TBBVersion;

use warnings;
use strict;
use FindBin;
use TBBTestSuite::Common qw(exit_error);
use Cwd qw(getcwd);
use File::Slurp;
use File::Temp;
use IO::CaptureOutput qw(capture_exec);
use LWP::Simple;
use Digest::SHA qw(sha256_hex);

my $options;
my $tbbgit_url = 'https://git.torproject.org/builders/tor-browser-bundle.git';
my @sign_users = ( 'mikeperry', 'gk', );
my @tbb_builders = ( 'mikeperry', 'gk', 'linus', 'erinn', 'boklm', );
my $clone_dir = "$FindBin::Bin/clones/tbb";

sub git_cmd_noerr {
    my $oldcwd = getcwd;
    chdir $clone_dir || exit_error "Error entering directory $clone_dir";
    my @res = capture_exec(@_);
    chdir $oldcwd;
    return @res;
}

sub git_cmd {
    my @res = git_cmd_noerr(@_);
    if (!$res[2]) {
        exit_error 'Error running ' . join(' ', @_) . ":\n" . $res[1];
    }
    return @res;
}

sub git_clone_pull {
    mkdir "$FindBin::Bin/clones" unless -d "$FindBin::Bin/clones";
    if (!-d $clone_dir) {
        system('git', 'clone', $tbbgit_url, $clone_dir) == 0
                || exit_error "Error cloning $tbbgit_url";
    }
    git_cmd('git', 'checkout', '--detach');
    git_cmd('git', 'fetch', '-p', 'origin', '+refs/heads/*:refs/heads/*');
}

sub set_gpgwrapper {
    my $keyring = '';
    foreach my $user (@sign_users) {
        $keyring .= " --keyring $FindBin::Bin/keyring/$user.gpg";
    }
    my $wrapper = <<EOF;
#!/bin/bash
set -e
if [ \$# -eq 4 ] && [ "\$1" = '--status-fd=1' ] && [ "\$2" = '--verify' ]
then
    gpgv $keyring "\$1" "\$3" "\$4" \\
              | sed 's/^\\[GNUPG:\\] EXPKEYSIG /\\[GNUPG:\\] GOODSIG /'
    exit \${PIPESTATUS[0]}
else
    exec gpg --no-default-keyring $keyring --trust-model always "\$@"
fi
EOF
    my $wrapper_file = "$options->{tmpdir}/gpgtbbgit";
    write_file($wrapper_file, $wrapper);
    chmod 0700, $wrapper_file;
    git_cmd('git', 'config', '--replace-all', '--local',
                'gpg.program', $wrapper_file);
}

sub get_taggerdate {
    my ($tagname) = @_;
    my ($out) = git_cmd('git', 'for-each-ref', '--format=%(taggerdate:raw)',
                        "refs/tags/$tagname");
    my @r = split ' ', $out;
    return $r[0];
}

sub latest_tagged_version {
    my ($branch, $min_date) = @_;
    my ($d) = git_cmd('git', 'describe', '--long', '--match=tbb-*', $branch);
    my @t = $d =~ m/^(tbb)-(.+)-(build.+)-.+-.+$/;
    return () unless @t;
    my $tag = join('-', @t);
    my (undef, undef, $sig_ok) = git_cmd_noerr('git', 'tag', '-v', $tag);
    return () unless $sig_ok;
    if ($min_date && get_taggerdate($tag) < $min_date) {
        return ();
    }
    return ($t[1], $t[2]);
}

sub branch_list {
    my $oldcwd = getcwd;
    chdir "$clone_dir/.git/refs/heads";
    my @res = glob '*';
    chdir $oldcwd;
    return @res;
}

sub latest_builds {
    $options = shift;
    my $build_done = shift // sub { 0; };
    my @res;
    git_clone_pull;
    set_gpgwrapper;
    my $two_weeks_ago = time - 1209600;
    foreach my $branch (branch_list) {
        my ($version, $build) = latest_tagged_version($branch, $two_weeks_ago);
        next unless $version;
        USER: foreach my $user (@tbb_builders) {
            my $buildname = "$version-$build";
            my $url = "https://people.torproject.org/~$user/builds/$version-$build/sha256sums-unsigned-build.txt";
            my $build_infos = {
                buildname => $buildname,
                version => $version,
                build => $build,
                url => $url,
                user => $user,
            };
            next if $build_done->($build_infos);
            my $sha = get($url);
            next unless $sha;
            my $sha_sig = get("$url.asc");
            next unless $sha_sig;
            my $sha_file = File::Temp->new;
            write_file($sha_file, $sha);
            my $sha_sig_file = File::Temp->new;
            write_file($sha_sig_file, $sha_sig);
            my (undef, undef, $success) = capture_exec('gpg', '--no-default-keyring',
                '--keyring', "$FindBin::Bin/keyring/$user.gpg", '--keyring',
                "$FindBin::Bin/keyring/torbrowser.gpg", '--verify',
                '--', $sha_sig_file, $sha_file);
            next unless $success;
            foreach my $file (split "\n", $sha) {
                (undef, $file) = split '  ', $file;
                chomp $file;
                my $file_url = "https://people.torproject.org/~$user/builds/$version-$build/$file";
                next USER unless head($file_url);
            }
            push @res, $build_infos;
        }
    }
    return @res;
}

1;
