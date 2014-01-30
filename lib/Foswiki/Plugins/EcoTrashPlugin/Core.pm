# Plugin for Foswiki Enterprise Collaboration Platform, http://Foswiki.org/
#
# Copyright (C) 2014 Timothe Litt, litt [at] acm.org
#
# Plugin interface Copyright (C) 2013 TWiki Contributors
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

package Foswiki::Plugins::EcoTrashPlugin::Core;

use warnings;
use strict;

use Error qw( :try );

use Foswiki::Func;

my $debug = $Foswiki::cfg{Plugins}{EcoTrashPlugin}{Debug} || 0;

# Web infrastructure topics - these aren't trash.  Note that ^ & $ are assumed
# to bracket the specified regex.  The don't because this regex is also used in
# a negative assertion.
# Users have no reason to change this; the cfg variable is to avoid a release
# if the infrastructure topic list changes unexpectedly.

my $protectedTopicsRe = $Foswiki::cfg{Plugins}{EcoTrashPlugin}{ProtectedTopics}
  || q((?:(?:Web(?:Atom|Changes|Home||Index|LeftBar(?:Example)?|Notify|TrashManager|Preferences|Rss|Search(?:Advanced)?|Statistics|TopicList|TopMenu))|(?:TrashAttachment)));

# Colors used for highlighting

my $errorColor     = '#ff0000';    # Red
my $errorColorTest = '#800080';    # Purple

# =========================
# Create trash management object
sub new {
    my ( $class, $baseWeb, $baseTopic ) = @_;

    my $this = {
        trashWeb => $Foswiki::cfg{TrashWebName} || 'Trash',
        trashTopic => $Foswiki::cfg{Plugins}{EcoTrashPlugin}{AttachTopic}
          || 'TrashAttachment',
        adminGroup => $Foswiki::cfg{Plugins}{EcoTrashPlugin}{AdminGroup}
          || $Foswiki::cfg{SuperAdminGroup}
          || 'FoswikiAdminGroup',
        pubDir         => Foswiki::Func::getPubDir(),
        dataDir        => Foswiki::Func::getDataDir(),
        baseWeb        => $baseWeb,
        baseTopic      => $baseTopic,
        log            => '',
        logFormat      => '%s',
        logErrorFormat => qq(<span style="color:$errorColor;">%s</span>),
        verbose        => 1,
    };
    bless( $this, $class );
    Foswiki::Func::writeDebug("- EcoTrashPlugin Core: Constructor") if ($debug);
    return $this;
}

# =========================
# Expand %TRASH{}%
sub VarTRASH {
    my $this = shift;

    #   my ( $session, $params, $theTopic, $theWeb ) = @_;
    my $params = $_[1];

    my $action = $params->{_DEFAULT} || $params->{action} || 'icon';
    Foswiki::Func::writeDebug("- EcoTrashPlugin: action=$action") if ($debug);

    if ( $action eq 'minage' ) {
        return $Foswiki::cfg{Plugins}{EcoTrashPlugin}{MinimumAge} || 0;
    }

    if ( $action eq 'maxage' ) {
        return $Foswiki::cfg{Plugins}{EcoTrashPlugin}{MaximumAge} || 0;
    }

    my $admingroup = $this->{adminGroup};
    if ( $action eq 'group' ) {
        return $admingroup;
    }

    if ( $action eq 'icon' ) {
        return $this->_icon;
    }

    if ( $action eq 'attachtopic' ) {
        return $this->{trashTopic};
    }

    unless ( Foswiki::Func::isGroupMember( $admingroup, undef ) ) {
        return "%RED%Must be a member of $admingroup%ENDCOLOR%";
    }

    if ( $action eq 'protected' ) {
        return $protectedTopicsRe;
    }

    if ( $action eq 'topicmove' ) {
        return $this->_topicmove(@_);
    }

    if ( $action eq 'listattachments' ) {
        return $this->_listattach(@_);
    }

    if ( $action eq 'listunclaimed' ) {
        return $this->_listunclaimed(@_);
    }

    if ( $action eq 'expiretime' ) {
        return
          time -
          ( 86400 * ( $Foswiki::cfg{Plugins}{EcoTrashPlugin}{MaximumAge} || 0 )
          );
    }
    if ( $action eq 'expiredate' ) {
        return Foswiki::Func::formatTime(
            (
                time - (
                    86400 * (
                        $Foswiki::cfg{Plugins}{EcoTrashPlugin}{MaximumAge} || 0
                    )
                )
            ),
            $Foswiki::cfg{DefaultDateFormat}
        );
    }

    return
      qq(%RED%%MAKETEXT{"Unknown function [_1]" args="$action"}%%ENDCOLOR%);
}

# =========================
# Format topic moved metadata
sub _topicmove {
    my $this = shift;
    my ( $session, $params ) = @_;

    my $topic = $params->{topic} || '';

    ( my $web, $topic ) =
      Foswiki::Func::normalizeWebTopicName( $this->{trashWeb}, $topic );

    unless ( $topic
        && Foswiki::Func::topicExists( $web, $topic ) )
    {
        return qq(%RED%%MAKETEXT{"[_1] is missing", args="$topic"}%%ENDCOLOR%);
    }

    my ( $meta, $topicTtext ) = Foswiki::Func::readTopic( $web, $topic );

    my @moved = $meta->find('TOPICMOVED');

    # Should only be one.
    my $moved = $moved[0] || {};
    foreach my $m ( @moved[ 1 .. $#moved ] ) {
        if ( ( $m->{date} || 0 ) > ( $moved->{date} || 0 ) ) {
            $moved = $m;
        }
    }
    my ( $rdate, $author, $rev, $comment ) = $meta->getRevisionInfo();

    $moved->{date} ||= $rdate;
    $moved->{from} ||= '';
    $moved->{to}   ||= "$web.$topic";
    $moved->{by}   ||= $author;

    my $text = $params->{format} || '$name $rev $author\n';
    $text = Foswiki::Func::decodeFormatTokens($text)
      ;    # Expand tokens in format, but NOT in metadata values

    my ( $fweb, $ftopic, $fname, $fpath );
    if ( $moved->{from} ) {
        ( $fweb, $ftopic ) =
          Foswiki::Func::normalizeWebTopicName( $web, $moved->{from} );
        $fname = "$fweb.$ftopic";
        $fpath = $fname;
        $fpath =~ s,\.,/,g;
    }
    else {
        ( $fweb, $ftopic, $fname, $fpath ) = ( '', '', '', '' );
    }

    my ( $tweb, $ttopic, $tname, $tpath );
    if ( $moved->{to} ) {
        ( $tweb, $ttopic ) =
          Foswiki::Func::normalizeWebTopicName( $web, $moved->{to} );
        $tname = "$tweb.$ttopic";
        $tpath = $tname;
        $tpath =~ s,\.,/,g;
    }
    else {
        ( $tweb, $ttopic, $tname, $tpath ) = ( '', '', '', '' );
    }

    my $restore;
    if ( $moved->{from} && !Foswiki::Func::topicExists( $fweb, $ftopic ) ) {
        $restore = '<a href="'
          . Foswiki::Func::getScriptUrl(
            $tweb, $ttopic, 'rename',
            newweb      => $fweb,
            newtopic    => $ftopic,
            nonwikiword => 1,
            confirm     => 1,
          )
          . '" class="foswikiButton" title="%MAKETEXT{"Returns topic to its original location"}%">%MAKETEXT{"Restore"}%</a>';
    }
    else {
        $restore = '<a href="'
          . Foswiki::Func::getScriptUrl(
            $tweb, $ttopic, 'rename',
            newweb      => 'Sandbox',
            nonwikiword => 1,
          )
          . '" class="foswikiButton" title="'
          . (
            $moved->{from}
            ? '%MAKETEXT{"Original topic name has been re-used.  Select a new name/web."}%'
            : '%MAKETEXT{"Original topic name is unknown.  Select a new name/web."}%'
          ) . '">%MAKETEXT{"Rehome"}%</a>';
    }

    $text =~
s{\$name}{join( '.', Foswiki::Func::normalizeWebTopicName( $web, $topic ))}egms;
    $text =~ s{\$rev}{$rev || ''}egms;
    $text =~ s{\$date}{$rdate || '0'}egms;
    $text =~
s{\$fdate}{Foswiki::Func::formatTime( ($rdate || 0), $Foswiki::cfg{DefaultDateFormat} )}egms;
    $text =~ s{\$user}{Foswiki::Func::getWikiName($author) || ''}egms;
    $text =~ s{\$from}{$moved->{from} || ''}egms;
    $text =~ s{\$to}{$moved->{to} || ''}egms;
    $text =~ s{\$tpath}{$tpath}gms;
    $text =~ s{\$ftopic}{$ftopic}egms;
    $text =~ s{\$fname}{$fname}egms;
    $text =~ s{\$ttopic}{$ttopic}egms;
    $text =~ s{\$tname}{$tname}egms;
    $text =~ s{\$mdate}{$moved->{date} || '0'}egms;
    $text =~
s{\$fmdate}{Foswiki::Func::formatTime( ($moved->{date} || 0), $Foswiki::cfg{DefaultDateFormat} )}egms;
    $text =~ s{\$mname}{Foswiki::Func::getWikiName($moved->{by}) || ''}egms;
    $text =~ s{\$restore}{$restore}gms;
    $text =~ s{\$comment}{$comment || ''}egms;

    return $text;
}

# =========================
# Attachments deleted from topics belong to the trashTopic
sub _listattach {
    my $this = shift;
    my ( $session, $params ) = @_;

    unless (
        Foswiki::Func::topicExists( $this->{trashWeb}, $this->{trashTopic} ) )
    {
        return
qq(%RED%%MAKETEXT{"[_1] is missing", args="$this->{trashTopic}"}%%ENDCOLOR%);
    }
    my ( $meta, $text ) =
      Foswiki::Func::readTopic( $this->{trashWeb}, $this->{trashTopic} );

    my @attached = $meta->find('FILEATTACHMENT');
    return Foswiki::Func::decodeFormatTokens( $params->{none} || '' )
      unless (@attached);

    my $format = $params->{format}
      || q($name $rev $size $date $user $hattr $comment$n);

    return (Foswiki::Func::decodeFormatTokens( $params->{header} || '' )
          . $this->_formatattach( \@attached, $format, 'attachment' )
          . Foswiki::Func::decodeFormatTokens( $params->{footer} || '' ) );
}

# =========================
# Attachments that don't belong to a topic
sub _listunclaimed {
    my $this = shift;
    my ( $session, $params ) = @_;

    my $pubTrash = "$this->{pubDir}/$this->{trashWeb}";

    # Check pub sub-directories of Trash.  If a corresponding topic
    # doesn't exist, report the stray files in pub.  This is done
    # even if the topic is protected.
    # Attachments may exist without metadata - intentionally, or
    # by mistake.

    my @unclaimed;
    if ( opendir( my $dh, $pubTrash ) ) {
        while ( ( my $fn = readdir($dh) ) ) {
            next if ( $fn =~ /^\.\.?/ );

            my $pPath = "$pubTrash/$fn";
            next unless ( -d $pPath );

            next if ( Foswiki::Func::topicExists( $this->{trashWeb}, $fn ) );

            # This directory doesn't correspond to an existing topic

            require File::Find;
            File::Find::find(
                {
                    follow            => 0,
                    dangling_symlinks => 0,
                    untaint           => 1,
                    untaint_pattern   => qr|^([-+@\w.,&\\/]+)$|,
                    wanted            => sub {
                        my $fn = $_;
                        my $fp = $File::Find::name || $File::Find::name;

                        return if ( $fn =~ /^\.\.?$/ || !-f $fp || -l $fp );
                        my @stat = stat(_);

                        return if ( $fp =~ /(^.*),v$/ && -e $1 );

                        my $to = substr(
                            $fp,
                            length($pubTrash) + 1,
                            length($fp) -
                              ( length($pubTrash) + 1 + 1 + length($fn) )
                        );
                        $to =~ s,/,.,g;
                        $to = "$this->{trashWeb}.$to.$fn";
                        push @unclaimed,
                          {    # metadata-ish to enable common formatting
                            name      => $fn,
                            size      => $stat[7],
                            date      => $stat[9],
                            moveddate => $stat[9],
                            user      => 'guest',
                            movedto   => $to,
                            comment   => q(%MAKETEXT{"Unclaimed file"}%),
                            attr      => '',
                            path      => '',
                            version   => 0,
                          };
                        return;
                    },
                },
                $pPath
            );
        }
        closedir($dh);
    }

    return Foswiki::Func::decodeFormatTokens( $params->{none} || '' )
      unless (@unclaimed);

    my $format = $params->{format}
      || q($name $rev $size $date $user $hattr $comment$n);

    return (Foswiki::Func::decodeFormatTokens( $params->{header} || '' )
          . $this->_formatattach( \@unclaimed, $format, 'unclaimed' )
          . Foswiki::Func::decodeFormatTokens( $params->{footer} || '' ) );
}

# =========================
# Apply user format to attachment metadata
sub _formatattach {
    my $this = shift;
    my ( $attached, $format, $type ) = @_;

    my $rsp = '';
    my $pub = $this->{pubDir};

    foreach my $att (
        sort {
            ( $a->{moveddate} || $a->{movedwhen} || $a->{date} || 0 )
              <=> ( $b->{moveddate} || $b->{movedwhen} || $b->{date} || 0 )
        } @$attached
      )
    {
        my $line = $format;
        $line = Foswiki::Func::decodeFormatTokens($line)
          ;    # Expand tokens in format, but NOT in metadata values

        # Doc doesn't agree with metadata code.  We try doc first,
        # then empirical.
        # From/to look like Web.Topic.file.ext.  A filename can
        # include '.', so I think this is ambiguous when subwebs exist...
        # Names can change in the move, and the source web may have
        # disappeared.  So I don't think we can solve this.
        my $ftopic =
          ( ( $att->{movedfrom} || $att->{movefrom} || '' ) =~
              /^([^.]+\.[^.]+)\.(.+)$/ )[0]
          || '';
        my $fname = $2 || '';
        my ( $fw, $ft ) = Foswiki::Func::normalizeWebTopicName( '', $ftopic );
        my $ttopic =
          ( ( $att->{movedto} || '' ) =~ /^(([^.]+)\.([^.]+))\.(.+)$/ )[0]
          || '';
        my $tname = $4 || '';
        my $tpath = "$2/$3/$4";
        my ( $tw, $tt ) =
          Foswiki::Func::normalizeWebTopicName( $this->{trashWeb}, $ttopic );
        next
          unless ( -f "$pub/$tpath" )
          ;    # Don't report if metadata points to a non-existent file

        my $restore;
        if ( $type eq 'unclaimed' ) {
            $restore = 'Run maintenance';
        }
        elsif ( $ftopic && Foswiki::Func::topicExists( $fw, $ft ) ) {
            $restore = '<a href="'
              . Foswiki::Func::getScriptUrl(
                $tw, $tt, 'rename',
                template    => 'restoreattachment',
                attachment  => $fname,
                newweb      => $fw,
                newtopic    => $ft,
                nonwikiword => 1,
                confirm     => 'on',
              )
              . '" class="foswikiButton" title="%MAKETEXT{"Returns attachment to its original topic"}%">%MAKETEXT{"Restore"}%</a>';
        }
        else {
            $restore = '<a href="'
              . Foswiki::Func::getScriptUrl(
                $tw, $tt, 'rename',
                template    => 'restoreattachment',
                attachment  => $fname,
                newweb      => $fw,
                nonwikiword => 1,
                confirm     => 'on',
              )
              . '" class="foswikiButton" title="'
              . (
                $ftopic
                ? '%MAKETEXT{"Original topic has been deleted.  Select a new topic."}%'
                : '%MAKETEXT{"Original topic name is unknown.  Select a new name/web."}%'
              ) . '">%MAKETEXT{"Rehome"}%</a>';
        }

        $line =~ s{\$name}{$att->{name} || ''}egms;
        $line =~ s{\$rev}{$att->{version} || '0'}egms;
        $line =~ s{\$path}{$att->{path} || ''}egms;
        $line =~ s{\$size}{$att->{size} || '0'}egms;
        $line =~ s{\$date}{$att->{date} || '0'}egms;
        $line =~
s{\$fdate}{Foswiki::Func::formatTime( ($att->{date} || 0), $Foswiki::cfg{DefaultDateFormat} )}egms;
        $line =~ s{\$user}{Foswiki::Func::getWikiName($att->{user}) || ''}egms
          ;    # REMOTE_USER doc, login-name actual.
        $line =~ s{\$attr}{$att->{attr} || ''}egms;    # E.g. h => hidden
        $line =~ s{\$from}{$att->{movedfrom} || $att->{movefrom} || ''}egms;
        $line =~ s{\$to}{$att->{movedto} || ''}egms;
        $line =~ s{\$tpath}{$tpath}gms;
        $line =~ s{\$ftopic}{$ftopic}egms;
        $line =~ s{\$fname}{$fname}egms;
        $line =~ s{\$ttopic}{$ttopic}egms;
        $line =~ s{\$tname}{$tname}egms;
        $line =~ s{\$mdate}{$att->{moveddate} || $att->{movedwhen} || ''}egms;
        $line =~
s{\$fmdate}{Foswiki::Func::formatTime( ($att->{moveddate} || $att->{movedwhen} || 0), $Foswiki::cfg{DefaultDateFormat} )}egms;
        $line =~
s{\$mname}{Foswiki::Func::getWikiName($att->{movedby} || $att->{moveby}) || ''}egms
          ;    # REMOTE_USER doc, login-name actual
        $line =~ s{\$restore}{$restore}gms;
        $line =~ s{\$comment}{$att->{comment} || ''}egms;
        $rsp .= $line;
    }
    return $rsp;
}

# =========================
# REST service (Management form POST)
sub RECYCLE {
    my $this = shift;

    #   my ( $session ) = @_;

    Foswiki::Func::writeDebug("- EcoTrashPlugin: action=recycle") if ($debug);

    my $query = Foswiki::Func::getCgiQuery();
    unless ( $query->request_method eq 'POST' ) {
        return $this->_error("Invalid request method");
    }

    my $admingroup = $this->{adminGroup};

    my $context = Foswiki::Func::getContext();
    unless ( $context->{authenticated} ) {
        return $this->_error("Not authenticated");
    }
    unless ( Foswiki::Func::isGroupMember( $admingroup, undef ) ) {
        return $this->_error("Must be a member of $admingroup");
    }

    # Foswiki/TWiki 5+ doesn't provide url_param and query_string returns form
    # items if present.
    # Scan uri in this case.  Set test (no deletions) mode from parameters.
    if ( $query->can('url_param') ) {
        if ( $query->url_param('debug') || $query->param('test_mode') ) {
            $this->{test} = 1;
        }
    }
    else {
        if (   $query->param('test_mode')
            || $query->uri =~ /^[^?]*\?\bdebug=on\b/ )
        {
            $this->{test} = 1;
        }
    }
    $this->{log} .= << 'CSS';
<style type="text/css">
.EcoTrashLog {
margin-left:20px;
margin-right:20px;
padding:10px;
}
CSS
    if ( $this->{test} ) {
        $this->{logErrorFormat} =~ s/$errorColor/$errorColorTest/g;
        $this->{log} .= << 'CSS';
.EcoTestMode {
border-style:outset;
border-width:10px;
background-repeat: repeat;
background-image: url(data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAFAAAABACAMAAAC6GQAEAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAMAUExURczMzP///wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAE5PEigAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAHdElNRQfZCgYTFB3F9gafAAAAB3RFWHRBdXRob3IAqa7MSAAAAAx0RVh0RGVzY3JpcHRpb24AEwkhIwAAAAp0RVh0Q29weXJpZ2h0AKwPzDoAAAAHdEVYdFNvdXJjZQD1/4PrAAAACHRFWHRDb21tZW50APbMlr8AAAAGdEVYdFRpdGxlAKju0icAAAAadEVYdFNvZnR3YXJlAFBhaW50Lk5FVCB2My41LjExR/NCNwAAAGlJREFUWEftzCESADEMw8De/z99BjLsBKRQJhkF7Ok+Rq5bUDAj5+buoY4WFMzIGez4v4NpQcGMvDd3D3W0oGBGzmDH/x1MCwpm5L25e6ijBQUzcgY7/u9gWlAwI+/N3UMdLSiYkUOf8wNaKwoB2NHlxAAAAABJRU5ErkJggg==);
opacity:0.5;
filter:alpha(opacity=50);
}
CSS
    }
    $this->{log} .= << 'CSS';
</style>
CSS

    # Dispatch on request type to generate response

    if ( $query->param("dodeletetopics") ) {
        $this->_recycle_selected( $query, 1, 'topics' );
    }
    elsif ( $query->param("dodeleteattach") ) {
        $this->_recycle_selected( $query, 1, 'attachments' );
    }
    elsif ( $query->param("dodeleteunclaimed") ) {
        $this->_recycle_selected( $query, 1, 'unclaimed' );
    }
    elsif ( $query->param('domaint') ) {
        $this->_maint( $query, 1 );
    }
    else {
        $this->{log} .= qq(---+!! Invalid request function\n);
    }

    # Return page (Uses a subset of Foswiki markup)

    my $return = $query->param('mgr_topic');
    $query->delete('endPoint');

    if ($return) {
        ( $this->{baseWeb}, $this->{baseTopic} ) =
          Foswiki::Func::normalizeWebTopicName( '', $return );
    }

    # Debug feature: Display raw TML if ?raw=on
    if ( $query->can('url_param') ) {
        $this->{log} = qq(<verbatim>$this->{log}</verbatim>)
          if ( $query->url_param('raw') || $query->param('raw') );
    }
    else {
        $this->{log} = qq(<verbatim>$this->{log}</verbatim>)
          if ( $query->uri =~ /^[^?]*\?\braw=on\b/ || $query->param('raw') );
    }
    require CGI;
    my $pub = Foswiki::Func::getPubUrlPath . '/' . $Foswiki::cfg{SystemWebName};
    return join(
        '',
        CGI::start_html(
            -title  => "Trash Management Results",
            -script => [
                {
                    -type => "text/javascript",
                    -src  => "$pub/JQueryPlugin/jquery.js",
                },
                {
                    -type => "text/javascript",
                    -src  => "$pub/JQueryPlugin/jquery-all.js",
                },
            ],
            -head => [
                CGI::Link(
                    {
                        -rel   => "stylesheet",
                        -href  => "$pub/JQueryPlugin/jquery-all.css",
                        -type  => "text/css",
                        -media => "all",
                    }
                ),
            ]
        ),
        Foswiki::Func::renderText(
            Foswiki::Func::expandCommonVariables(
                $this->{log}, 'WebTrashManagerResults', 'Trash', undef
            ),
            $this->{trashWeb}
        ),
        qq(</div>),
        qq(<div style="margin-top:20px;"><a class="foswikiLink" href="),
        Foswiki::Func::getScriptUrl(
            $this->{baseWeb}, $this->{baseTopic}, 'view'
        ),
        qq(">Return to $this->{baseTopic}</a></div>),
        CGI::end_html(),
    );
}

# =========================
# GUI-commanded expunge of selected items
sub _recycle_selected {
    my $this = shift;
    my ( $query, $format, $items ) = @_;

   # Because this is a management function, I'm not worrying about I18n for now.

    $this->{log} .=
        qq(---+!! )
      . $this->_icon
      . $this->{trashWeb}
      . qq( Management Results\n\n<div class="EcoTrashLog !EcoTestMode">\n);
    $this->{log} .=
      qq(__Processing in test mode, nothing will be expunged__ \n\n)
      if ( $this->{test} );

    my $pubTrash  = "$this->{pubDir}/$this->{trashWeb}";
    my $dataTrash = "$this->{dataDir}/$this->{trashWeb}";

    # Topic deletions

    my @topics = $query->param('delete_topic');
    $query->delete( 'delete_topic', "dodeletetopics" );
    if ( $items eq 'topics' && @topics ) {
        $this->_log( 2, qq(---++!! Topics expunged from !$this->{trashWeb}\n) );

        foreach my $topic (@topics) {
            $topic =~ s/\.\.//g;
            $topic =~ /^(.*)$/;
            $topic = $1;

            next
              unless (
                Foswiki::Func::topicExists( $this->{trashWeb}, $topic ) );

            $this->{logFormat} = "   * %s";

        # We should remove per the metadata, but as noted above, it's not valid.
            $this->_log( 1, "!$topic\n" );

            if ( -d qq($pubTrash/$topic) ) {
                $this->{logFormat} = "      * %s";
                $this->_log( 1,
                    qq(Inspecting attachment directory $pubTrash/$topic\n) );
                $this->{logFormat} = "         * %s";
                my $s = $this->_removeDir(qq($pubTrash/$topic));
                $this->{logFormat} = "      * %s";
                if ($s) {
                    if ( $this->_rmdir(qq($pubTrash/$topic)) ) {
                        $this->_log( 1,
                            "Expunged attachment directory $pubTrash/$topic\n"
                        );
                    }
                    else {
                        $this->_log( 0,
"Failed to expunge attachment directory $pubTrash/$topic: $!\n"
                        );
                    }
                }
            }
            else {
                ;    #                $this->_log( 1, "* No attachments\n" );
            }
            $this->{logFormat} = "      * %s";
            if ( $this->_unlink("$dataTrash/$topic.txt") ) {
                $this->_log( 1,
                    "Expunged topic container $dataTrash/$topic.txt\n" );
            }
            else {
                $this->_log( 0,
"Failed to expunge topic container $dataTrash/$topic.txt: $!\n"
                );
            }
            if ( -e "$dataTrash/$topic.txt,v" ) {
                if ( $this->_unlink("$dataTrash/$topic.txt,v") ) {
                    $this->_log( 1,
                        "Expunged topic history $dataTrash/$topic.txt,v\n" );
                }
                else {
                    $this->_log( 0,
"Failed to expunge topic history $dataTrash/$topic.txt,v: $!\n"
                    );
                }
            }
            if ( -e "$dataTrash/$topic.lease" ) {
                if ( $this->_unlink("$dataTrash/$topic.lease") ) {
                    $this->_log( 1,
                        "Expunged topic lease $dataTrash/$topic.lease\n" );
                }
                else {
                    $this->_log( 0,
"Failed to expunge topic history $dataTrash/$topic.lease: $!\n"
                    );
                }
            }
        }
    }

    # Attachment deletions

    my @attach = $query->param('delete_attach');
    $query->delete( 'delete_attach', "dodeleteattach" );

    if ( $items eq 'attachments' && @attach ) {
        $this->{logFormat} = "%s";

        $this->_log( 1,
            qq(---++!! Attachments expunged from !$this->{trashWeb}\n) );
        $this->{logFormat} = "   * %s";

        my ( $meta, $text ) =
          Foswiki::Func::readTopic( $this->{trashWeb}, $this->{trashTopic} );

        foreach my $file (@attach) {
            $file =~ s/\.\.//g;
            $file =~ /^(.*)$/;
            $file = $1;

            $meta->remove( 'FILEATTACHMENT', $file );

            if ( $this->_unlink("$pubTrash/$this->{trashTopic}/$file") ) {
                $this->_log( 1,
                    "Expunged attachment $pubTrash/$this->{trashTopic}/$file\n"
                );
            }
            else {
                $this->_log( 0,
"Failed to expunge attachment $pubTrash/$this->{trashTopic}/$file: $!\n"
                );
            }
            if ( -e "$pubTrash/$this->{trashTopic}/$file,v" ) {
                if ( $this->_unlink("$pubTrash/$this->{trashTopic}/$file,v") ) {
                    $this->_log( 1,
"Expunged attachment history $pubTrash/$this->{trashTopic}/$file,v\n"
                    );
                }
                else {
                    $this->_log( 0,
"Failed to expunge history $pubTrash/$this->{trashTopic}/$file,v: $!\n"
                    );
                }
            }
        }

        unless ( $this->{test} ) {
            Foswiki::Func::saveTopic(
                $this->{trashWeb},
                $this->{trashTopic},
                $meta, $text,
                {
                    minor   => 1,
                    dontlog => 1,
                }
            );
        }
    }

    # Unclaimed attachment deletions

    my @unclaimed = $query->param('delete_unclaimed');
    $query->delete( 'delete_unclaimed', "dodeleteunclaimed" );

    if ( $items eq 'unclaimed' && @unclaimed ) {
        $this->{logFormat} = "%s";
        $this->_log( 1,
            qq(---++!! Unclaimed attachments expunged from !$this->{trashWeb}\n)
        );
        $this->{logFormat} = "   * %s";

        foreach my $file (@unclaimed) {
            $file =~ s/\.\.//g;
            $file =~ /^(.*)$/;
            $file = $1;

            my $name = $file;
            $name =~ s/^$this->{trashWeb}\.//;
            $name =~ /^([^.]+)[.](.+)$/;
            my $topic = $1;
            $name = $2;

            if ( $this->_unlink("$pubTrash/$topic/$name") ) {
                $this->_log( 1,
                    "Expunged attachment !$topic: $pubTrash/$topic/$name\n" );
            }
            else {
                $this->_log( 0,
"Failed to expunge attachment !$topic: $pubTrash/$topic/$name: $!\n"
                );
            }
            if ( -e "$pubTrash/$topic/$name,v" ) {
                if ( $this->_unlink("$pubTrash/$topic/$name,v") ) {
                    $this->_log( 1,
"Expunged attachment history !$topic: $pubTrash/$topic/$name,v\n"
                    );
                }
                else {
                    $this->_log( 0,
"Failed to expunge history !$topic: $pubTrash/$topic/$name,v: $!\n"
                    );
                }
            }
        }
    }

    # Summary

    $this->{logFormat} = "%s";
    unless ( @topics && $items eq 'topics'
        || @attach && $items eq 'attachments'
        || @unclaimed && $items eq 'unclaimed' )
    {
        $this->_log( 1, "---++!! Nothing selected, nothing was done.\n" );
    }

    return;
}

# =========================
# CLI service for sweeper
sub ecotrashSweeper {
    my $this = shift;

    my $context = Foswiki::Func::getContext();
    unless ( $context->{command_line} ) {
        die "ecotrashSweeper: Only runs from the command line\n";
    }

    # Protect against common user error - expecting -t to work.
    # It doesn't work with the V5+ Engine::CLI parser.

    foreach my $arg (@ARGV) {
        if ( $arg =~ /^-/ && $arg !~ /=/ ) {
            print STDERR "Switches require a value.  Specify  $arg=1\n";
            exit(1);
        }
    }
    my $query = Foswiki::Func::getCgiQuery();
    $this->{verbose} =
      !( $query && ( $query->param('quiet') || $query->param('q') ) );
    $this->{test} =
      ( $query && ( $query->param('test') || $query->param('t') ) );

    $this->{logErrorFormat} = "ERROR: %s";
    $this->{exitStatus}     = 0;

    $this->_maint( $query, 0 );
    return $this->{exitStatus};
}

# =========================
# Do the web maintenance - for CLI or GUI
sub _maint {
    my $this = shift;

    my ( $query, $format ) = @_;

    my $start;
    if ($format) {
        $this->{log} .=
            qq(---+!! )
          . $this->_icon
          . $this->{trashWeb}
          . qq( Maintenance Results\n\n<div class="EcoTrashLog !EcoTestMode">\n);
        $this->{log} .=
          qq(__Processing in test mode, nothing will be expunged__\n\n)
          if ( $this->{test} );
        $this->{log} .= "<pre>";
        $start = length $this->{log};
    }

    my $pub       = $this->{pubDir};
    my $pubTrash  = "$pub/$this->{trashWeb}";
    my $dataTrash = "$this->{dataDir}/$this->{trashWeb}";

    # Check pub sub-directories of pubTrash.  If a corresponding topic doesn't
    # exist, create one and attach the stray files.  This is an error no matter
    # what the age constraint.

    if ( opendir( my $dh, $pubTrash ) ) {
        while ( ( my $fn = readdir($dh) ) ) {
            next if ( $fn =~ /^\.\.?/ );

            $fn =~ s/\.\.//g;
            $fn =~ /^(.*)$/;
            $fn = $1;

            my $pPath = "$pubTrash/$fn";
            next unless ( -d $pPath );

            next if ( Foswiki::Func::topicExists( $this->{trashWeb}, $fn ) );

            $this->_log( 0,
                "Attachment directory $pPath has no corresponding topic.\n" );
            my @files;
            if ( opendir( my $dir, $pPath ) ) {
                while ( ( my $afn = readdir($dir) ) ) {
                    next if ( $afn =~ /^\.\.?/ );
                    push @files, $afn;
                }
                closedir $dir;
            }
            else {
                $this->log( 0, "Unable to process directory $pPath: $!\n" );
                next;
            }
            unless (@files) {
                $this->_removeDir($pPath);
                if ( $this->_rmdir(qq($pPath)) ) {
                    $this->_log( 1,
                        "Expunged empty attachment directory $pPath\n" );
                }
                else {
                    $this->_log( 0,
"Failed to expunge empty attachment directory $pPath: $!\n"
                    );
                }
                next;
            }
            my $error = '';
            unless ( $this->{test} ) {
                Foswiki::Func::saveTopic(
                    $this->{trashWeb},
                    $fn, undef, '',
                    {
                        dontlog => 1,
                        minor   => 1,
                    }
                );
            }
            if ($error) {
                $this->_log( 0,
"Failed to create missing topic $this->{trashWeb}.$fn: $error\n"
                );
                next;
            }
            $this->_log( 1, "Created topic $this->{trashWeb}.$fn\n" );

            Foswiki::Func::pushTopicContext( $this->{trashWeb}, $fn );
            foreach my $file (@files) {
                my ( $attname, $oldname ) =
                  Foswiki::Func::sanitizeAttachmentName($file);

                unless ( $this->{test} ) {
                    my $error;
                    try {
                        my @stat = stat("$pPath/$file");
                        $error = Foswiki::Func::saveAttachment(
                            $this->{trashWeb},
                            $fn, $attname,
                            {
                                dontlog => 1,
                                comment =>
"Unclaimed file recovered by $this->{trashWeb} maintenance",
                                hide     => 1,
                                file     => "$pPath/$file",
                                filesize => $stat[7],
                                filedate => $stat[9],
                            }
                        );
                    }
                    catch Foswiki::AccessControlException with {
                        $error = shift;
                    }
                    catch Error::Simple with {
                        $error = shift;
                    }
                    otherwise {
                        $error = shift;
                    };
                }
                if ($error) {
                    $this->_log(
                        0,
"Failed to save attachment $this->{trashWeb}.$fn $file as $attname: ",
                        ( ref $error ? $error->stringify : $error )
                    );
                }
                else {
                    $this->_log( 1,
                        "Attached $file to $this->{trashWeb}.$fn as $attname\n"
                    );
                }
            }
            Foswiki::Func::popTopicContext();
        }
        closedir($dh);
    }

    my $maxage = $Foswiki::cfg{Plugins}{EcoTrashPlugin}{MaximumAge} || 0;
    if ($maxage) {

        # Handle removing items that are $maxage days old, or older

        $maxage = time - ( $maxage * 86400 );

        # Process TrashAttachment topic's metadata.  Remove metadata that points
        # to non-existent files.Look for files deleted before the cutoff.

        if (
            Foswiki::Func::topicExists(
                $this->{trashWeb}, $this->{trashTopic}
            )
          )
        {
            my ( $meta, $text ) =
              Foswiki::Func::readTopic( $this->{trashWeb},
                $this->{trashTopic} );
            my $changed = 0;

            my @attached = $meta->find('FILEATTACHMENT');
            foreach my $att (@attached) {
                my $ttopic =
                  ( ( $att->{movedto} || '' ) =~ /^(([^.]+)\.([^.]+))\.(.+)$/ )
                  [0] || '';
                my $tname = $4 || '';
                my $tpath = "$2/$3/$4";
                unless ( -f "$pub/$tpath" ) {

                    # Metadata points to non-existent file, remove it
                    $this->_log(
                        1,
                        "Removing stale metadata for $att->{name} rev ",
                        ( $att->{version} || 0 ), "\n"
                    );
                    $meta->remove( 'FILEATTACHMENT', $att->{name} );
                    $changed = 1 unless ( $this->{test} );
                    next;
                }

                my $date =
                     $att->{moveddate}
                  || $att->{movedwhen}
                  || ( stat(_) )[9]
                  || 0;

                if ( $date && $date <= $maxage ) {
                    $meta->remove( 'FILEATTACHMENT', $att->{name} );

                    if ( $this->_unlink("$pub/$tpath") ) {
                        $this->_log( 1, "Expunged attachment $pub/$tpath\n" );
                    }
                    else {
                        $this->_log( 0,
                            "Failed to expunge attachment $pub/$tpath: $!\n" );
                    }
                    if ( -e "$pub/$tpath,v" ) {
                        if ( $this->_unlink("$pub/$tpath,v") ) {
                            $this->_log( 1,
                                "Expunged attachment history $pub/$tpath,v\n" );
                        }
                        else {
                            $this->_log( 0,
                                "Failed to expunge history $pub/$tpath,v: $!\n"
                            );
                        }
                    }
                }
            }
            if ($changed) {
                Foswiki::Func::saveTopic(
                    $this->{trashWeb},
                    $this->{trashTopic},
                    $meta, $text,
                    {
                        minor   => 1,
                        dontlog => 1,
                    }
                );
            }
        }

        # Check each topic in the Trash web's directory.
        # A topic is deleted with all its attachments intact; topics are aged
        #as a whole.
        #
        # The metadata is not always valid.

        foreach my $topic ( Foswiki::Func::getTopicList( $this->{trashWeb} ) ) {

            # Since the attachment metadata is unreliable, assume that any files
            # in the corresponding pub/Trash/topicname belong to the topic.

            next if ( $topic =~ /^$protectedTopicsRe$/ );

            my ( $meta, $text ) =
              Foswiki::Func::readTopic( $this->{trashWeb}, $topic );

            my @moved = $meta->find('TOPICMOVED');
            my $moved = $moved[0];
            if ( @moved > 1 ) {    # Should only be 1, but just in case...
                foreach my $m ( @moved[ 1 .. $#moved ] ) {
                    if ( $m->{date} > $moved->{date} ) {
                        $moved = $m;
                    }
                }
            }

           # Deleted topics should have a moved date.  Use revision date if not.

            my $date = $moved->{date} || ( $meta->getRevisionInfo() )[0];

            if ( $date && $date <= $maxage ) {
                if ( -d qq($pubTrash/$topic) ) {
                    if ( $this->_removeDir(qq($pubTrash/$topic)) ) {
                        $this->_log( 1,
                            "Expunged attachments$pubTrash/$topic\n" );
                    }
                    else {
                        $this->_log( 0,
"Failed to expunge attachments $pubTrash/$topic: $!\n"
                        );
                    }
                    if ( $this->_rmdir(qq($pubTrash/$topic)) ) {
                        $this->_log( 1,
                            "Expunged attachment directory $pubTrash/$topic\n"
                        );
                    }
                    else {
                        $this->_log( 0,
"Failed to expunge attachment directory $pubTrash/$topic: $!\n"
                        );
                    }
                }
                else {
                    ;    #                 $this->_log( 1, "No attachments\n" );
                }
                if ( $this->_unlink("$dataTrash/$topic.txt") ) {
                    $this->_log( 1, "Expunged topic $dataTrash/$topic.txt\n" );
                }
                else {
                    $this->_log( 0,
                        "Failed to expunge topic $dataTrash/$topic.txt: $!\n" );
                }
                if ( -e "$dataTrash/$topic.txt,v" ) {
                    if ( $this->_unlink("$dataTrash/$topic.txt,v") ) {
                        $this->_log( 1,
                            "Expunged topic history $dataTrash/$topic.txt,v\n"
                        );
                    }
                    else {
                        $this->_log( 0,
"Failed to expunge topic history $dataTrash/$topic.txt,v: $!\n"
                        );
                    }
                }
                if ( -e "$dataTrash/$topic.lease" ) {
                    if ( $this->_unlink("$dataTrash/$topic.lease") ) {
                        $this->_log( 1,
                            "Expunged topic lease $dataTrash/$topic.lease\n" );
                    }
                    else {
                        $this->_log( 0,
"Failed to expunge topic history $dataTrash/$topic.lease: $!\n"
                        );
                    }
                }
            }
        }
    }

    if ($format) {
        my $end = length $this->{log};
        $this->{log} .= "</pre>\n";
        $this->_log( 1, "---++!! No action was taken\n" )
          if ( $end == $start );
    }

    return;
}

# =========================
# Removes all files/directories under $path
# Does not remove $path (primarily for log formatting reasons)

sub _removeDir {
    my $this = shift;
    my ($path) = @_;

    my $rval = 1;

    require File::Find;
    File::Find::find(
        {
            follow            => 0,
            dangling_symlinks => sub {
                my ( $name, $dir ) = @_;
                $name = "$dir/$name";
                $name =~ /^(.*)$/;
                $name = $1;

                if ( $this->_unlink($name) ) {
                    $this->_log( 1, "Removed dangling symlink $name\n" );
                }
                else {
                    $this->_log( 0,
                        "Failed to remove dangling symlink $name: $!\n" );
                    $rval = 0;
                }
                return;
            },
            untaint         => 1,
            untaint_pattern => qr|^([-+@\w.,&\\/]+)$|,
            bydepth         => 1,
            wanted          => sub {
                my $fn = $_;
                my $fp = $File::Find::name || $File::Find::name;
                return if ( $fn =~ /^\.\.?$/ );
                $fp =~ /^(.*)$/;
                $fp = $1;

                if ( ( -d $fp ) ? $this->_rmdir($fp) : $this->_unlink($fp) ) {
                    $this->_log( 1, "Expunged $fp\n" );
                }
                else {
                    $this->_log( 0, "Failed to expunge $fp:$!\n" );
                    $rval = 0;
                }
                return;
            },
        },
        $path
    );

    return $rval;
}

# =========================
# Makes all paths
sub _logpath {
    my $this = shift;
    my ($path) = @_;

    my ( $pub, $data ) = ( $this->{pubDir}, $this->{dataDir} );
    $pub  =~ s,^(.*/).*$,$1,;
    $data =~ s,^(.*/).*$,$1,;

    $path =~ s,(^|\b|\s|:)(?:$pub|$data)/?,$1,gms;
    return $path;
}

# =========================
sub _unlink {
    my $this = shift;

    return scalar @_ if ( $this->{test} );

    return unlink(@_);
}

# =========================
sub _rmdir {
    my $this = shift;

    return 1 if ( $this->{test} );

    return rmdir( $_[0] );
}

# =========================
# Logging
sub _log {
    my $this = shift;

    my $level = shift;    # 0 - Errors.  1 - Status

    $this->{exitStatus}++ unless ($level);

    return unless ( $this->{verbose} );

    my $text = $this->_logpath( join( '', @_ ) );

    if ($level) {
        $this->{log} .= sprintf( $this->{logFormat}, $text );
    }
    else {
        my $fmt = $this->{logFormat};
        $fmt =~ s/%s/$this->{logErrorFormat}/gms;
        my $n = chomp $text;
        $fmt .= "\n" if ($n);
        $this->{log} .= sprintf( $fmt, $text );
    }
    if ( Foswiki::Func::getContext->{command_line} ) {
        print $this->{log};
        $this->{log} = '';
    }
    return;
}

# =========================
# Abort a REST request with an error page
sub _error {
    my $this = shift;

    my $query = Foswiki::Func::getCgiQuery();
    $query->delete('endPoint');

    my $topic = qq{$this->{baseWeb}.$this->{baseTopic}};
    require CGI;
    return join(
        '',
        CGI::start_html(),
        qq(<div>EcoTrashPlugin: <span style="color:$errorColor;">),
        join( '', @_ ),
        qq(</span></div><p>),
        qq(<a href="),
        Foswiki::Func::getScriptUrl(
            $this->{baseWeb}, $this->{baseTopic}, 'view'
        ),
        qq(>Return to $topic</a>),
        CGI::end_html(),
    );
}

# =========================
# Image is lgpl license from http://www.mricons.com/icon/14122/32/trash-empty
# (Designer: www.oxygen-icons.org)
sub _icon {
    return (
        q(<img width="32" height="32" title="" alt="Trash manager icon" src=")
          . q(data:image/png;base64,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)
          . q(" />) );
}

1;

# EOF

