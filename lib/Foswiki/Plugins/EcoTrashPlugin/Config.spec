# ---+ Extensions
# ---++ EcoTrashPlugin

# **STRING 40**
# Managing the Trash web requires membership in this group.
# If not defined, defaults to <b>{SuperAdminGroup}</b>.
$Foswiki::cfg{Plugins}{EcoTrashPlugin}{AdminGroup} = '';

# **NUMBER 40**
# To protect deleted items for a minimum time, specify
# the retention period (in days).  Zero allows immediate deletion.
$Foswiki::cfg{Plugins}{EcoTrashPlugin}{MinimumAge} = 0;

# **NUMBER 40**
# To expire and expunge deleted items when they reach a particular age, specify
# the maximum age (in days).  Items older than this value will be deleted when the cron job
# runs.  Zero specifies infinite retention.
$Foswiki::cfg{Plugins}{EcoTrashPlugin}{MaximumAge} = 0;

# **STRING 40 EXPERT**
# Name of the trash attachment topic.
$Foswiki::cfg{Plugins}{EcoTrashPlugin}{AttachTopic} = 'TrashAttachment';

# **REGEX 80 EXPERT**
# Regular expression that defines which topics in the Trash web are NOT trash.  This must include
# {AttachTopic} and various infrastructure topics.  The expression must NOT include ^ and $, but
# must match as if it was embedded between those.  Users should not be creating any protected topics
# in the Trash web.  This setting is only to be used if the infrastructure topic list changes.
# The default is hard-coded in the plugin.
$Foswiki::cfg{Plugins}{EcoTrashPlugin}{ProtectedTopics} = '';

# **BOOLEAN EXPERT**
# Debug plugin. See output in data/debug.txt
$Foswiki::cfg{Plugins}{EcoTrashPlugin}{Debug} = 0;

1;
