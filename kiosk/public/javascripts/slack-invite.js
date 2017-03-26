$(document).ready(function() {
  var all_slack_names = new Bloodhound({
    datumTokenizer: Bloodhound.tokenizers.whitespace,
    queryTokenizer: Bloodhound.tokenizers.whitespace,
    prefetch: '/slack_names.json'
  });

  // passing in `null` for the `options` arguments will result in the default
  // options being used
  $('.slack_name').typeahead(null, {
    name: 'slack_name',
    source: all_slack_names
  });

  var me_poll = function(){
    $.ajax({url:'/me',dataType:'json',timeout: 500, async: true}).done(function(){
      $('body').loadingOverlay('remove');
      // if we are on the registration page, send new user home
      if(window.location.href.indexOf('register') != -1){
        window.location.href = '/';
      }
    }).fail(function(){
      setTimeout(me_poll, 350);
    });
  }

  $('#slackFormSubmit').click(function(e){
    e.preventDefault();
    $.ajax({url:'/ping',
            dataType:'json',
            timeout: 500
          }).done(function(){
              $.ajax({url: '/send_slack_invite',
                data: {'slack_name':$('#slack_name').val()},
                type: 'POST',
                success: function(e){
                  $('#registerModal').modal('hide');
                  $('body').loadingOverlay();
                  alert('click the link in your slack client to get setup!');
                  me_poll();
                }
              });
          }).fail(function(){alert("We don't see you on the network...")})
  });
});
