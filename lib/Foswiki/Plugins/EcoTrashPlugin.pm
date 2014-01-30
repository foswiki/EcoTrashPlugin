# Plugin for Foswiki Enterprise Collaboration Platform, http://Foswiki.org/
#
# Copyright (C) 20114 Timothe Litt, litt [at] acm.org
# Plugin interface:
# Copyright (C) 2013 Peter Thoeny, peter[at]thoeny.org
# Copyright (C) 2013 TWiki Contributors
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html
#
# As per the GPL, removal of this notice is prohibited.

package Foswiki::Plugins::EcoTrashPlugin;

use warnings;
use strict;

use Carp;
use Foswiki::Func;

# =========================
our $VERSION           = 'V1.002';
our $RELEASE           = '2014-01-29';
our $SHORTDESCRIPTION  = 'Manage the trash web';
our $NO_PREFS_IN_TOPIC = 1;

# =========================
my $debug = $Foswiki::cfg{Plugins}{EcoTrashPlugin}{Debug} || 0;
my $core;
my $baseWeb;
my $baseTopic;

# =========================
sub initPlugin {
    ( $baseTopic, $baseWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 1.2 ) {
        Foswiki::Func::writeWarning(
            "Version mismatch between EcoTrashPlugin and Plugins.pm");
        return 0;
    }

    $core = undef;
    Foswiki::Func::registerTagHandler( 'TRASH', \&VarTRASH );
    Foswiki::Func::registerRESTHandler( 'Recycle', \&RECYCLE );

    # Plugin initialized correctly
    Foswiki::Func::writeDebug(
        "- EcoTrashPlugin: initPlugin( " . "$baseWeb.$baseTopic ) is OK" )
      if $debug;

    return 1;
}

# All functions are dynamically loaded and invoked as object methods.

# =========================
sub AUTOLOAD {
    our $AUTOLOAD;

    unless ($core) {
        require Foswiki::Plugins::EcoTrashPlugin::Core;
        $core =
          Foswiki::Plugins::EcoTrashPlugin::Core->new( $baseWeb, $baseTopic );
    }

    my $method = $AUTOLOAD;
    $method =~ s/^.*:://;
    $method = $core->can($method);

    confess("EcoTrashPlugin: $AUTOLOAD is not implemented") unless ($method);

    unshift @_, $core;
    goto &$method;
}

1;

# EOF
