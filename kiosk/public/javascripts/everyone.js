$(function() {


    $('#worker-modal').on('show.bs.modal', function (event) {
    var button = $(event.relatedTarget) // Button that triggered the modal
    var name = button.data('name') // Extract info from data-* attributes
    var slackname = button.data('slackname') // Extract info from data-* attributes
    var title = button.data('title') // Extract info from data-* attributes
    var slack_id = button.data('slackid') // Extract info from data-* attributes
    var avatar = button.data('avatar') // Extract info from data-* attributes
  // If necessary, you could initiate an AJAX request here (and then do the updating in a callback).
  // Update the modal's content. We'll use jQuery here, but you could use a data binding library or other methods instead.
    var modal = $(this)
    var is_online = true
    
    $.ajax({url:'/online', type: "get", data: {slack_id: slack_id}}).done(function(){
      
      is_online = true;
      $('.slack_buttons button').on('click',function(el){
      var msg = $(this).html();
      
      $.ajax({
          type: 'POST',
          // make sure you respect the same origin policy with this url:
          // http://en.wikipedia.org/wiki/Same_origin_policy
          url: '/slack_ping/',
          data: {
              'to': slack_id,
              'message': msg
          }
        }).done(function() {
          // what do we do with success?
        }).fail(function(data){
          console.log(data.responseJSON.msg);
        }).always(function(data){
          $.wait(function() {
            console.log('waited')
          }, 6);
        })  
    })
      // setup online stuff
    }).fail(function(){
      
      is_online = false;
      
    });

    
    modal.find('.worker-name').text(name);
    modal.find('.avatar_container img').attr("src", avatar);
    modal.find('.modal-profile').text(title);
  })

});
