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
  }).bind('change blur', validateSelection);

  function validateSelection() {
    if(all_slack_names.get($(this).val())[0] === undefined) { $(this).val('') }
  }

  var me_poll = function(){
    $.ajax({url:'/me',
            dataType:'json',
            timeout: 500,
            async: true})
        .done(function(){
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
                data: {'slack_name':$('#magic_slack').val()},
                type: 'POST',
                success: function(e){
                  $('#registerModal').modal('hide');
                  $('body').loadingOverlay();
                  alert('click the link in your slack client to get setup!');
                  me_poll();
                },
                error: function(e){
                  alert("That isn't your slack ID...");
                  $('#magic_slack').val('');
                }
              });
          }).fail(function(){alert("We don't see you on the network...")})
  });

  var ping_poll = function(){
    $.ajax({url:'/ping',dataType:'json',timeout: 500, async: true}).done(function(){
      $('#ping-status').hide();
      $('#register').show();
      $('#slack_me_up').show();
      $('.form-group').show();
    }).fail(function(){
      $('#ping-status').show();
      $('#register').hide();
      $('#slack_me_up').hide();
      $('.form-group').hide();
      setTimeout(ping_poll, 350);
    });
  }


  $.ajax({url:'/me', dataType: "json"}).done(function(d){
    if (d['success'] === true) {
      if (d['data']['real_name'] === 'Reception') {
        // send reception home. no registreation for them
        window.location.href = '/'
      }

      $('input[name=real_name]').val(d['data']['real_name']);
      $('input[name=slack_name]').val(d['data']['slack_name']);
      var avatar = d['data']['avatar'];

      if (avatar.indexOf('http') === -1 && avatar.indexOf('/') > 0) {
        avatar = "/" + avatar;
      };

      $("#img_holder").html('<img src="'+ avatar +'" alt="yourimage" />');
    }
  }).fail(function(){
    console.log('not yet registered');
  });
    // don't let people register if they can't be pinged!
    ping_poll();
    $("input[type!='file']").attr("required", true);
});

