@findUser = (userId) ->
  if userId?
    Meteor.users.findOne(userId) ? {}
  else
    {}

@findUsername = (username) ->
  Meteor.users.findOne
    username: username

## Need to escape dots in usernames.
@escapeUser = escapeGroup
@unescapeUser = unescapeGroup

if Meteor.isServer
  Meteor.publish 'users', (group) ->
    @autorun ->
      if groupRoleCheck group, 'admin', findUser @userId
        Meteor.users.find {},
          roles: 1
      else
        @ready()

  Meteor.publish 'userData', ->
    @autorun ->
      if @userId
        Meteor.users.find
          _id: @userId
        , fields:
            roles: 1
            'services.dropbox.id': 1
      else
        @ready()
else  ## client
  Meteor.subscribe 'userData'
