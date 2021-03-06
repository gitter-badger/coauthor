sharejsEditor = 'ace'  ## 'ace' or 'cm'; also change template used in message.jade

Template.registerHelper 'titleOrUntitled', ->
  titleOrUntitled @.title

Template.registerHelper 'isFile', ->
  @.format == 'file'

Template.registerHelper 'children', ->
  if @children
    children = Messages.find _id: $in: @children
                 .fetch()
    children = _.sortBy children, (child) => @children.indexOf child._id
    ## Use canSee to properly fake non-superuser mode.
    children = (child for child in children when canSee child)
    for child in children
      child.depth = (@depth ? 0) + 1
    children

Template.rootHeader.helpers
  root: ->
    if @root
      Messages.findOne @root

Template.registerHelper 'formatTitle', ->
  sanitizeHtml formatTitle @format, @title

Template.badMessage.helpers
  message: -> Router.current().params.message

orphans = (message) ->
  descendants = []
  Messages.find
    $or: [
      root: message
    , _id: message
    ]
  .forEach (descendant) ->
    descendants.push descendant.children... if descendant.children?
  Messages.find
    root: message
    _id: $nin: descendants

Template.message.helpers
  subscribers: ->
    subscribers =
      for subscriber in messageSubscribers @_id
        linkToAuthor @group, subscriber
    if subscribers.length > 0
      subscribers.join(', ')
    else
      '(none)'
  orphans: ->
    orphans @_id
  orphanCount: ->
    count = orphans(@_id).count()
    if count > 0
      pluralize count, 'orphaned subthread'

Template.message.onCreated ->
  @autorun ->
    setTitle titleOrUntitled Template.currentData()?.title

Template.message.onRendered ->
  $('body').scrollspy
    target: 'nav.contents'
  $('nav.contents').affix
    offset: top: $('#top').outerHeight true
  $('.affix-top').height $(window).height() - $('#top').outerHeight true
  $(window).resize ->
    $('.affix-top').height $(window).height() - $('#top').outerHeight true
  $('nav.contents').on 'affixed.bs.affix', ->
    $('.affix').height $(window).height()
  $('nav.contents').on 'affixed-top.bs.affix', ->
    $('.affix-top').height $(window).height() - $('#top').outerHeight true
  $('[data-toggle="tooltip"]').tooltip()

  ## Give focus to first Title input, if there is one.
  titles = $('input.title')
  if titles.length
    titles[0].focus()

editing = (self) ->
  Meteor.user()? and Meteor.user().username in (self.editing ? [])

idle = 1000   ## one second

Template.registerHelper 'deletedClass', ->
  if @deleted
    'deleted'
  else if @published
    'published'
  else
    'unpublished'

submessageCount = 0

messageRaw = new ReactiveDict
messageFolded = new ReactiveDict
messageHistory = new ReactiveDict
messageKeyboard = new ReactiveDict
defaultKeyboard = 'normal'

Template.submessage.onCreated ->
  @count = submessageCount++
  @editing = new ReactiveVar null
  @autorun =>
    return unless Template.currentData()?
    #@myid = Template.currentData()._id
    if editing Template.currentData()
      @editing.set Template.currentData()._id
    else
      @editing.set null
    #console.log 'automathjax'
    automathjax()

#Session.setDefault 'images', {}
images = {}
id2template = {}
scrollToLater = null

onDragStart = (url, id) -> (e) ->
  #url = pathFor 'message',
  #  group: group
  #  message: id
  e.dataTransfer.setData 'text/plain', url
  e.dataTransfer.setData 'application/coauthor', id

Template.submessage.onRendered ->
  ## Random message background color (to show nesting).
  #@firstNode.style.backgroundColor = '#' +
  #  Math.floor(Math.random() * 25 + 255 - 25).toString(16) +
  #  Math.floor(Math.random() * 25 + 255 - 25).toString(16) +
  #  Math.floor(Math.random() * 25 + 255 - 25).toString(16)

  ## Drag/drop support.
  if @find('.focusButton')? and @data._id?
    url = "coauthor:#{@data._id}"
    if @data.format == 'file'
      formatted = formatBody @data.format, @data.body
      if "class='odd-file'" not in formatted and
         "class='bad-file'" not in formatted
        url = formatted
        $(@find('.panel-body')).find('img, video').each (i, elt) =>
          elt.addEventListener 'dragstart', onDragStart url, @data._id
    @find('.focusButton').addEventListener 'dragstart', onDragStart url, @data._id
    #@find('.focusButton').addEventListener 'dragend', (e) =>
    #  e.dataTransfer.setData 'text/plain', "<IMG SRC='#{url}'>"

  ## Fold deleted messages by default on initial load.
  messageFolded.set @data._id, true if @data.deleted

  ## Fold referenced attached files by default on initial load.
  #@$.children('.panel').children('.panel-body').find('a[href|="/gridfs/fs/"]')
  #console.log @$ 'a[href|="/gridfs/fs/"]'
  tid = @data._id
  id2template[@data._id] = @
  scrollToMessage @data._id if scrollToLater == @data._id
  attachment = @data.format == 'file'
  #images = Session.get 'images'
  subimages = @images = []
  $(@firstNode).children('.panel-body').find('img[src^="/gridfs/fs/"]')
  .each ->
    id = url2file @.getAttribute('src')
    subimages.push id
    if id not of images
      images[id] =
        attachment: null
        count: 0
    if attachment
      images[id].attachment = tid
    else
      images[id].count += 1
    if images[id].count > 0 and images[id].attachment? and not messageFolded.get(images[id].attachment)?
      messageFolded.set images[id].attachment, true
    #console.log images
  #Session.set 'images', images

scrollDelay = 750

@scrollToMessage = (id) ->
  if id of id2template
    template = id2template[id]
    $.scrollTo template.firstNode, scrollDelay,
      easing: 'swing'
      onAfter: ->
        $(template.find 'input.title').focus()
  else
    scrollToLater = id

Template.submessage.onDestroyed ->
  for id in @images
    if id of images
      images[id].count -= 1

historify = (x) -> () ->
  history = messageHistory.get @_id
  if history?
    history[x]
  else
    @[x]

tabindex = (i) -> 
  1 + 20 * Template.instance().count + parseInt(i ? 0)

Template.submessage.helpers
  tabindex: tabindex
  tabindex7: -> tabindex 7
  tabindex9: -> tabindex 9
  here: ->
    Router.current().route.getName() == 'message' and
    Router.current().params.message == @_id
  nothing: {}
  editingRV: -> Template.instance().editing.get()
  editingNR: -> Tracker.nonreactive -> Template.instance().editing.get()
  hideIfEditing: ->
    if Template.instance().editing.get()
      'hidden'
    else
      ''
  #myid: -> Tracker.nonreactive -> Template.instance().myid
  #editing: -> editing @
  config: ->
    ti = Tracker.nonreactive -> Template.instance()
    (editor) =>
      #console.log 'config', editor.getValue(), '.'
      ti.editor = editor
      #editor.container.addEventListener 'drop', (e) =>
      #  e.preventDefault()
      #  if id = e.dataTransfer.getData('application/coauthor')
      #    #switch @format
      #    #  when 'latex'
      #    #    e.dataTransfer.setData('text/plain', "\\href{#{id}}{}")
      #    e.dataTransfer.setData('text/plain', "<IMG SRC='coauthor:#{id}'>")
      switch sharejsEditor
        when 'cm'
          editor.getInputField().setAttribute 'tabindex', 1 + 20 * ti.count + 19
          #editor.meteorData = @  ## currently not needed, also dunno if works
          #editor.on 'change', onChange
          editor.setOption 'styleActiveLine', true
          editor.setOption 'matchBrackets', true
          editor.setOption 'lineWrapping', true
          editor.setOption 'lineNumbers', true
          editor.setOption 'theme',
            switch theme()
              when 'dark'
                'blackboard'
              when 'light'
                'default'
              else
                theme()
          #editor.setShowFoldWidgets true
          editor.setOption 'mode',
            switch ti.data.format
              when 'markdown'
                'gfm'  ## Git-flavored Markdown
              when 'html'
                'text/html'
              else
                ti.data.format
          #editor.setOption 'mode', 'javascript'
          #require 'codemirror/mode/javascript/javascript'
        when 'ace'
          editor.textInput.getElement().setAttribute 'tabindex', 1 + 20 * ti.count + 19
          #editor.meteorData = @  ## currently not needed, also dunno if works
          editor.$blockScrolling = Infinity
          #editor.on 'change', onChange
          editor.setTheme 'ace/theme/' +
            switch theme()
              when 'dark'
                'vibrant_ink'
              when 'light'
                'chrome'
              else
                theme()
          editor.setShowPrintMargin false
          editor.setBehavioursEnabled true
          editor.setShowFoldWidgets true
          editor.getSession().setUseWrapMode true
          #console.log "setting format to #{ti.data.format}"
          #editor.getSession().setMode 'ace/mode/html'
          editor.getSession().setMode "ace/mode/#{ti.data.format}"
          #editor.setOption 'spellcheck', true

  keyboard: ->
    capitalize messageKeyboard.get(@_id) ? defaultKeyboard
  activeKeyboard: (match) ->
    if (messageKeyboard.get(@_id) ? defaultKeyboard) == match
      'active'
    else
      ''

  deleted: historify 'deleted'
  published: historify 'published'

  tex2jax: ->
    history = messageHistory.get(@_id) ? @
    if history.format in mathjaxFormats
      'tex2jax'
    else
      ''
  title: historify 'title'
  formatTitle: ->
    history = messageHistory.get(@_id) ? @
    title = history.title
    return title unless title
    if messageRaw.get @_id
      "<CODE CLASS='raw'>#{_.escape title}</CODE>"
    else
      title = formatTitle history.format, title
      sanitized = sanitizeHtml title
      console.warn "Sanitized '#{title}' -> '#{sanitized}'" if sanitized != title
      sanitized
  formatBody: ->
    history = messageHistory.get(@_id) ? @
    body = history.body
    return body unless body
    if messageRaw.get @_id
      "<PRE CLASS='raw'>#{_.escape body}</PRE>"
    else
      body = formatBody history.format, body
      sanitized = sanitizeHtml body
      console.warn "Sanitized '#{body}' -> '#{sanitized}'" if sanitized != body
      sanitized

  isFile: -> @format == 'file'
  canEdit: -> canEdit @_id
  canDelete: -> canDelete @_id
  canUndelete: -> canUndelete @_id
  canPublish: -> canPublish @_id
  canUnpublish: -> canUnpublish @_id
  canSuperdelete: -> canSuperdelete @_id
  canReply: -> canPost @group, @_id
  canAttach: -> canPost @group, @_id

  history: -> messageHistory.get(@_id)?
  forHistory: ->
    _id: @_id
    history: messageHistory.get @_id

  folded: -> messageFolded.get @_id
  raw: -> messageRaw.get @_id

Template.registerHelper 'messagePanelClass', ->
  if @deleted
    'panel-danger message-deleted'
  else if @published
    'panel-primary message-published'
  else
    'panel-warning message-unpublished'

@linkToAuthor = (group, user) ->
  link = pathFor 'author',
    group: group
    author: user
  "<a class='author' href='#{link}'>#{user}</a>"

Template.registerHelper 'formatCreator', ->
  linkToAuthor @group, @creator

Template.registerHelper 'formatAuthors', ->
  a = for own author, date of @authors when author != @creator or date.getTime() != @created.getTime()
        "#{linkToAuthor @group, unescapeUser author} #{formatDate date, 'on '}"
  if a.length > 0
    ', edited by ' + a.join ", "

Template.submessage.events
  'click .foldButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    messageFolded.set @_id, not messageFolded.get @_id

  'click .rawButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    messageRaw.set @_id, not messageRaw.get @_id

  'click .editButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id  #e.target.getAttribute 'data-message'
    if editing @
      Meteor.call 'messageEditStop', message
    else
      Meteor.call 'messageEditStart', message

  'click .publishButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    ## Stop editing if we are publishing.
    if not @published and editing @
      Meteor.call 'messageEditStop', message
    Meteor.call 'messageUpdate', message,
      published: not @published

  'click .deleteButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = t.data._id
    ## Stop editing if we are deleting.
    if not @deleted and editing @
      Meteor.call 'messageEditStop', message
    Meteor.call 'messageUpdate', message,
      deleted: not @deleted

  'click .editorKeyboard': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    messageKeyboard.set @_id, kb = e.target.getAttribute 'data-keyboard'
    switch sharejsEditor
      when 'cm'
        if kb == 'normal'
          t.editor.setOption 'keyMap', ''
        else
          #require 'codemirror/keymap/vim'
          #require 'codemirror/keymap/emacs'
          t.editor.setOption 'keyMap', kb
      when 'ace'
        t.editor.setKeyboardHandler if kb == 'normal' then '' else 'ace/keyboard/' + kb
    $(e.target).parent().dropdown 'toggle'

  'click .editorFormat': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    Meteor.call 'messageUpdate', t.data._id,
      format: format = e.target.getAttribute 'data-format'
    $(e.target).parent().dropdown 'toggle'
    #console.log "setting format to #{format}"
    switch sharejsEditor
      when 'cm'
        Template.instance().editor.setOption 'mode', format
      when 'ace'
        Template.instance().editor.getSession().setMode "ace/mode/#{format}"

  'keyup input.title': (e, t) ->
    e.stopPropagation()
    message = t.data._id
    Meteor.clearTimeout t.timer
    t.timer = Meteor.setTimeout ->
      Meteor.call 'messageUpdate', message,
        title: e.target.value
    , idle

  'click .replyButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    message = @_id
    if canPost @group, @_id
      Meteor.call 'messageNew', @group, @_id, (error, result) ->
        if error
          console.error error
        else if result
          Meteor.call 'messageEditStart', result
          scrollToMessage result
          #Router.go 'message', {group: group, message: result}
        else
          console.error "messageNew did not return problem -- not authorized?"

  'click .historyButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    if messageHistory.get(@_id)?
      messageHistory.set @_id, null
    else
      messageHistory.set @_id, _.clone @

  'click .superdeleteButton': (e) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.show 'superdelete', @

  'click .replaceButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()

Template.superdelete.events
  'click .shallowSuperdeleteButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.hide()
    Meteor.call 'messageSuperdelete', t.data._id
  'click .deepSuperdeleteButton': (e, t) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.hide()
    recurse = (message) ->
      msg = Messages.findOne message
      for child in msg.children
        recurse child
      Meteor.call 'messageSuperdelete', message
    recurse t.data._id
  'click .cancelButton': (e) ->
    e.preventDefault()
    e.stopPropagation()
    Modal.hide()

Template.messageHistory.onCreated ->
  @diffsub = @subscribe 'messages.diff', @data._id

Template.messageHistory.onRendered ->
  @autorun =>
    diffs = MessagesDiff.find
        id: @data._id
      ,
        sort: ['updated']
      .fetch()
    return if diffs.length < 2  ## don't show a zero-length slider
    ## Accumulate diffs
    for diff, i in diffs
      if i >= 0
        for own key, value of diffs[i-1]
          unless key of diff
            diff[key] = value
    @slider?.destroy()
    @slider = new Slider @$('input')[0],
      #min: 0                 ## min and max not needed when using ticks
      #max: diffs.length-1
      #value: diffs.length-1  ## doesn't update, unlike setValue method below
      ticks: [0...diffs.length]
      ticks_snap_bounds: 999999999
      tooltip: 'always'
      tooltip_position: 'bottom'
      formatter: (i) ->
        if i of diffs
          formatDate(diffs[i].updated) + '\n' + diffs[i].updators.join ', '
        else
          i
    @slider.setValue diffs.length-1
    #@slider.off 'change'
    @slider.on 'change', (e) =>
      messageHistory.set @data._id, diffs[e.newValue]
    messageHistory.set @data._id, diffs[diffs.length-1]

uploader = (template, button, input, callback) ->
  Template[template].events {
    "click .#{button}": (e, t) ->
      e.preventDefault()
      e.stopPropagation()
      t.find(".#{input}").click()
    "change .#{input}": (e, t) ->
      callback e.target.files, e, t
      e.target.value = ''
    "dragenter .#{button}": (e) ->
      e.preventDefault()
      e.stopPropagation()
    "dragover .#{button}": (e) ->
      e.preventDefault()
      e.stopPropagation()
    "drop .#{button}": (e, t) ->
      e.preventDefault()
      e.stopPropagation()
      callback e.originalEvent.dataTransfer.files, e, t
  }

attachFiles = (files, e, t) ->
  message = t.data._id
  group = t.data.group
  for file in files
    file.callback = (file2) ->
      Meteor.call 'messageNew', group, message, null,
        format: 'file'
        title: file2.fileName
        body: file2.uniqueIdentifier
    file.group = group
    Files.resumable.addFile file, e

uploader 'messageAttach', 'attachButton', 'attachInput', attachFiles

replaceFiles = (files, e, t) ->
  message = t.data._id
  group = t.data.group
  if files.length != 1
    console.error "Attempt to replace #{message} with #{files.length} files -- expected 1"
  else
    file = files[0]
    file.callback = (file2) ->
      Meteor.call 'messageUpdate', message,
        format: 'file'
        title: file2.fileName
        body: file2.uniqueIdentifier
    file.group = group
    Files.resumable.addFile file, e

uploader 'messageReplace', 'replaceButton', 'replaceInput', replaceFiles

Template.messageAuthor.helpers
  creator: ->
    "!" + @creator
