$(document).ready(function() {

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

