$(function() {
  $('#front-door').on('click', function(e) {

    $.ajax({ url: '/downstairs_door'}).done(function(data){
      $('#front-door').css('background-color', '#ececec');
      $('#front-door').text('Opened!');
      $('#front-door').animateCss('pulse');

    }).fail(function(data) {
      $('#front-door').animateCss('shake');
      d = JSON.parse(data.responseText);
      $('#front-door').tooltip({title: d['msg'],
                                trigger: 'manual',
                                placement: 'right'}).tooltip('show');

      setTimeout(function() { $('#front-door').tooltip('hide'); }, 2000);
    }).always(function(){
      setTimeout(function() {
        $('#front-door').text('Open Front Door');
        $('#front-door').css('background-color', '#b0e61d');
      }, 1000);
    })
    
  });

});
