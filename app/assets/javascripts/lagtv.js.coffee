window.Lagtv =
  Models: {}
  Collections: {}
  Views: {}
  Routers: {}
  init: ->
    $('.dropdown-toggle').dropdown()
    
    $('.nav-tabs a').click (e) ->
      e.preventDefault()
      $(this).tab('show')
    
    $('.nav-tabs a:first').tab('show')

    $("[data-href]").click ->
      url = $(this).data("href")
      if(url.length > 0)
        location.href = url

    $(".suppress_click").click (ev) ->
      ev.stopPropagation()

    build_selected_querystring = ->
      querystring = "?"
      $("input.bulk_selection:checked").each ->
        querystring += "selected%5B%5D=" + $(this).val() + "&"
      return querystring

    $(".bulk_download_replays").click (ev) ->
      ev.stopPropagation()
      querystring = build_selected_querystring()
      
      if querystring.length > 1
        location.href = '/replays/download' + querystring

    $(".bulk_update_replays").click (ev) ->
      ev.stopPropagation()
      querystring = build_selected_querystring()
      new_status = $("#new_status").val()
      
      if querystring.length > 1 && new_status.length > 0
        location.href = '/replays/bulk_update' + querystring + "status=" + new_status


$(document).ready ->
  Lagtv.init()
