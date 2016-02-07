//= require jquery
//= require bootstrap
//= require_tree .

$(function() {
  var es = new EventSource('/feed');
  var new_people = [];
  $("input[type!='file']").attr("required", true);
  es.onmessage = function(e) {
    //console.log( "Got message", e )
  };

  es.addEventListener('message', function(e) {
    new_people = JSON.parse(e.data);
    add_remove_workers(new_people);
    check_last_seen();


  }, false);

  $.ajax({url:'/is_registered'}).done(function(data){
    if (data==='true') {
      $('.left_column').hide();
      $('.right_column').show();
      console.log('registered!');
    }else{
      $('.left_column').show();
      $('.right_column').hide();
      console.log('not registered');
    }
  });

  es.addEventListener('open', function(e) {
    console.log('Connection was opened.');
  }, false);

  es.addEventListener('error', function(e) {
    if (e.readyState == EventSource.CLOSED) {
      console.log('closed');
    }
  }, false);


  var w;

  var Worker = {
    setup_and_add: function(worker_object) {
            var klass = worker_object.device_name.replace(/\./g, "");
            Worker.grab_worker();
            Worker.set_avatar(worker_object.avatar);
            Worker.set_name(worker_object);
            Worker.add_class("."+klass);
            Worker.add_to_board(worker_object);
          },
    grab_worker: function(){
                   w = $('.worker').first().clone().removeClass('hidden');
                 },
    set_image: function(string){
      $('img', w).attr('src', string);
    },
    set_name: function(worker_data){
                $('.tape', w ).text(worker_data.name || sanitize_name(worker_data.device_name));
                $(w).attr("data-name", (worker_data.name || worker_data.device_name));
                $(w).attr("data-devicename", worker_data.device_name);
                $(w).attr("data-slackname", worker_data.slack_name);
              },
    set_avatar: function(avatar_url){
                  $('.avatar_container img', w).attr('src', avatar_url || "/images/visitor_art@1x-21d82dcb.png");
                },
    add_class: function(device_name){
                 w.addClass(device_name.replace(/\./g, ""));
               },
    add_to_board: function(worker_data){
                    Worker.add_slack();
                    Welcome.move_logo_and_welcomes();
                    $(w).children('.pin_and_avatar_container').addClass("animated").addClass("swing" + (Math.floor(((Math.random() * 2) + 1))).toString());
                    $('.right_column .row').append( w );
                    $('.newcomer h3').text(worker_data.name || sanitize_name(worker_data.device_name));
                    $('.newcomer_avatar img').attr('src', worker_data.avatar || "/images/visitor_art@1x-21d82dcb.png");
                    $('.newcomer_avatar, .newcomer').show().removeClass('animated').removeClass('bounceOutUp').addClass('animated bounceInDown');
                    $('.newcomer_avatar, .newcomer').one('webkitAnimationEnd mozAnimationEnd MSAnimationEnd oanimationend animationend', function(e) {
                      $(this).removeClass('bounceInDown').addClass('bounceOutUp');
                      Worker.redraw();

                    });
                  },
    add_slack: function(){
      $(w).click(function(){
        //if me, go to register
        //if slackname, send slack ping
        var to='';
        var worker = $(this);
        if ($(this).data('slackname') === false) {
          to = $(this).data('name');
        }else{
          to = $(this).data('slackname');
        }
        $.ajax({
          type: 'POST',
          // make sure you respect the same origin policy with this url:
          // http://en.wikipedia.org/wiki/Same_origin_policy
          url: '/ping/',
          data: {
              'to': to
          }
        });
        $(this).removeClass('animated').removeClass('swing2');
        $(this).addClass("animated").addClass("swing2");
        $(this).one('webkitAnimationEnd mozAnimationEnd MSAnimationEnd oanimationend animationend', function(e) {
          $(this).removeClass('animated').removeClass('swing2');
        });
      });
    },
    remove_worker: function(k) {
                     $( k ).addClass("animated bounceOutDown");
                     $('.bounceOutDown').one('webkitAnimationEnd mozAnimationEnd MSAnimationEnd oanimationend animationend', function(e) {
                       $(this).remove();
                       Worker.redraw();
                     });
                   },
    redraw: function() {
              var w = $('.worker').length;
              if ( w <= 6 ) {
                $('.board').removeClass('med small xsmall').addClass('large');
              } else if ( w <= 12 ) {
                $('.board').removeClass('small xsmall large').addClass('med');
              } else if ( w <= 24 ) {
                $('.board').removeClass('xsmall large med').addClass('small');
              } else {
                $('.board').removeClass('large med small').addClass('xsmall');
              }
            }
  };

  var add_remove_workers = function(w){

    w.map(function(worker_data){
      data_attribute = "[data-name='" + (worker_data.name || worker_data.device_name) + "']";
      data_attribute_device = "[data-name='" + worker_data.device_name + "']";
      $element = $(data_attribute);
      if ($element.length > 0) {
        $element.attr("data-lastseen", $.now());
        change_avatar(worker_data, data_attribute);
        data_attribute_worker = "[data-devicename='" + worker_data.device_name + "']";
        if ( $(data_attribute_worker).find(".tape").text() !== ( worker_data.name || sanitize_name(worker_data.device_name) ) ) {
          //console.log("this is the problem");
          Worker.remove_worker(data_attribute_worker);
        }
      } else {
        Worker.setup_and_add(worker_data);
        if (worker_data.name) {
          //console.log("No this is the problem");
          Worker.remove_worker(data_attribute_device);
        }
      }

    });
  };


  var sanitize_name = function(name){
    var name_change = name.replace(/(s\-).*/, "");
        name_change = name_change.replace(/\-.*/, "");
        name_change = name_change.replace(/siP.*/, "");
        name_change = name_change.replace(/iP.*/, "");
        name_change = name_change.replace(/iM.*/, "");
        name_change = name_change.replace(/\..*/, "");
        if (name_change === "") {
          name_change = "ANONYMOUS";
        }
        return name_change;
  };


  var check_last_seen = function() {
    $('.worker').each(function(num, wk){
      // console.log("not inside if yet");
      // console.log(wk);
      // console.log($(wk).attr('data-lastseen'));
      // console.log($.now() - 5000);
      worker_redraw();
      if (parseInt($(wk).attr('data-lastseen')) < ($.now() - 900000) && $(wk).find('.tape').text() !== "Ted" ) {
        // console.log("inside if");
        Worker.remove_worker(wk);
      }
    });
  };


  var change_avatar = function(user_param, data_attribute){
    var element = $(data_attribute).find('.avatar_container img');
    if (typeof user_param.avatar == "string" && user_param.avatar != element.attr('src')) {
      $(data_attribute).find(".avatar_container img").attr('src',user_param.avatar);
    }
  };

  var Welcome = {
    move_logo_and_welcomes: function() {
                   $('.logo').addClass("animated rubberBand");
                   $('.welcomes').addClass("animated tada");
                   $('.welcomes, .logo').one('webkitAnimationEnd mozAnimationEnd MSAnimationEnd oanimationend animationend', function(e) {
                      $(this).removeClass('animated').removeClass('tada').removeClass('rubberBand');
                    });
                 }

  };

var filter = function(){
  var workers=$('.worker[data-name]').map(function(d){$(this).hide();return {device_name:$(this).data('devicename'),name:$(this).data('name'),class:$(this).data('devicename').split('.').join(""),obj:$(this)}})
  var options={keys:['name','slackname']};
  var f = new Fuse(workers,options);
  var q = $("input").val();
  var found = [];
  if (q.length>0) {
    found = f.search($("input").val());
    $(found).each(function(i,v){$(v.obj).show();});
  }else{
    $('.worker[data-name]').each(function(i,v){$(v).show();});
  }
  worker_redraw();
}

var t = null;
$("input").keyup(function(){
    if (t) {
        clearTimeout(t);
    }
    t = setTimeout(filter(), 200);
});


var worker_redraw = function(){
  var w = $('.worker').length;
  if ( w <= 6 ) {
    $('.board').removeClass('med small xsmall').addClass('large');
  } else if ( w <= 12 ) {
    $('.board').removeClass('small xsmall large').addClass('med');
  } else if ( w <= 24 ) {
    $('.board').removeClass('xsmall large med').addClass('small');
  } else {
    $('.board').removeClass('large med small').addClass('xsmall');
  }
}

});

