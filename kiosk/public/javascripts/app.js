$(function() {

  window.setInterval(function(){
    // every hour refresh the page
    // for the reception kiosk
    window.location.href = window.location.href;
  },1000 * 60 * 60);
  // should probably use
  // http://stackoverflow.com/questions/4644027/how-to-automatically-reload-a-page-after-a-given-period-of-inactivity

  var es = new EventSource('/feed');
  var new_people = [];

  es.addEventListener('message', function(e) {
    data = JSON.parse(e.data);

    new_people = jQuery.grep( data, function(d){
      return d.type === 'device'});

    msgs = jQuery.grep( data, function(d){return d.type === 'msg'});
    msgs.forEach(onmessage);
    add_remove_workers(new_people);

    check_last_seen();
  }, false);

  es.addEventListener('open', function(e) {
    console.log('Connection was opened.');
  }, false);

  es.addEventListener('error', function(e) {
    if (e.readyState == EventSource.CLOSED) {
      console.log('closed');
    }else{
      window.location.href='/'; // reload page on error
    }
  }, false);

  // sends the user to register if unregistered,
  // otherwise, sets up the reception kiosk keyboard
  $.ajax({url:'/is_registered'}).done(function(data){
    if (data==='true') {
      $.ajax({url:'/me', dataType: "json"}).done(function(d){
        window.me = d['data']; // ugly hack.
        if (d['data']['real_name'] === 'Reception') {
           $(":text").onScreenKeyboard({'draggable': true,
                                       'topPosition': '90%',
                                       'leftPosition': '5%'});
        }
      });
      console.log('registered!');
    }else{
      if(window.location.href.indexOf('register') === -1){
        console.log('send to register');
        //window.location.href='/register'
      }
    }
  });

  // handles inbound messages
  // should refactor most of this into Worker class
  var onmessage = function(msg) {
    console.log(msg);

    slack_name = msg['user'].replace('@','');

    var options = {
      title: "message from:@"+slack_name,
      content: msg['msg'],
      trigger:'manual',
      placement: 'auto'
    }

    $worker = $('[data-slackname='+slack_name+']')
    $worker.popover('destroy');

    // scrolling so the worker is in the middle
    var elOffset = $worker.offset().top;
    var elHeight = $worker.height();
    var windowHeight = $(window).height();
    var offset;

    if (elHeight < windowHeight) {
      offset = elOffset - ((windowHeight / 2) - (elHeight / 2));
    }
    else {
      offset = elOffset;
    }
    $('html, body').animate({scrollTop:offset}, 600,'swing');
    Worker.animate_worker($worker,'bounce')
    $worker.popover(options).popover('show');
  }

// the main worker management code is below.

  var w; // stores the worker we are currently operating on.

  var Worker = {
    setup_and_add: function(worker_object) {
            var klass = worker_object.device_name.replace(/\./g, "");
            Worker.grab_worker();
            Worker.set_avatar(worker_object.avatar);
            Worker.set_name(worker_object);
            Worker.add_class("."+klass);
            Worker.add_to_board(worker_object);
            Worker.set_popover_timeout();
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
                $(w).attr("data-online",     worker_data.online);
                $(w).attr("data-devicename", worker_data.device_name);
                $(w).attr("data-slackname",  worker_data.slack_name);
                $(w).addClass('online-'+worker_data.online); // future
              },
    set_avatar: function(avatar_url){
                  $('.avatar_container img', w).attr('src', avatar_url || "/images/visitor_art@1x-21d82dcb.png");
                },
    set_popover_timeout: function(){
                  // this is the thing that hides the popover and resets it.
                  $(w).on('shown.bs.popover', function () {
                    console.log('popover shown!');
                    var $pop = $(this);
                    setTimeout(function () {
                      $pop.popover('destroy');
                      // $pop.setContent();
                      // $pop.$tip.addClass($pop.options.placement);
                    }, 6000);
                  });
                },
    add_class: function(device_name){
                 w.addClass(device_name.replace(/\./g, ""));
               },
    add_to_board: function(worker_data){
                    Worker.add_slack();
                    Welcome.move_logo_and_welcomes();
                    $(w).children('.pin_and_avatar_container').addClass("animated").addClass("swing" + (Math.floor(((Math.random() * 2) + 1))).toString());
                    $('.workers.row').append( w );
                    $('.newcomer h3').text(worker_data.name || sanitize_name(worker_data.device_name));
                    $('.newcomer_avatar img').attr('src', worker_data.avatar || "/images/visitor_art@1x-21d82dcb.png");
                    $('.newcomer_avatar, .newcomer').show().removeClass('animated').removeClass('bounceOutUp').addClass('animated bounceInDown');
                    $('.newcomer_avatar, .newcomer').one('webkitAnimationEnd mozAnimationEnd MSAnimationEnd oanimationend animationend', function(e) {
                      $(this).removeClass('bounceInDown').addClass('bounceOutUp');
                      Worker.redraw();
                    })
                  },
    add_slack: function(){
      $(w).click(function(e){
        //if me, go to register
        //if slackname, send slack ping
        var to='';
        var worker = $(this);
        if ($(this).data('slackname') === false) {
          to = $(this).data('name');
        }else{
          to = $(this).data('slackname');
        }
        worker.children('.pin_and_avatar_container').tooltip('destroy');
        $.ajax({
          type: 'POST',
          // make sure you respect the same origin policy with this url:
          // http://en.wikipedia.org/wiki/Same_origin_policy
          url: '/slack_ping/',
          data: {
              'to': to
          }
        }).done(function() {

          Worker.animate_worker(worker,'swing2');

          worker.children('.pin_and_avatar_container').tooltip({title:"Pinged!",trigger: 'manual', placement: 'auto'}).tooltip('show');

        }).fail(function(data) {
          d=JSON.parse(data.responseText);

          Worker.animate_worker(worker,'shake');
          worker.children('.pin_and_avatar_container').tooltip({title:d['msg'],trigger: 'manual', placement: 'auto'}).tooltip('show');

        }).always(function(){
          $.wait(function(){
            worker.children('.pin_and_avatar_container').tooltip('destroy');
          }, 6);
        });

      });
    },
    animate_worker: function(el,animation){
      el.removeClass('animated').removeClass(animation);
      el.addClass("animated").addClass(animation);
      el.one('webkitAnimationEnd mozAnimationEnd MSAnimationEnd oanimationend animationend', function(e) {
        el.removeClass('animated').removeClass(animation);
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
  }


  var add_remove_workers = function(w){
    // this function need some love.
    w.map(function(worker_data){
      // if worker_data == window.me, then skip adding

      data_attribute = "[data-name='" + (worker_data.name || worker_data.device_name) + "']";
      data_attribute_device = "[data-name='" + worker_data.device_name + "']";
      $element = $(data_attribute);
      if ($element.length > 0) {
        // the worker was already there, updating
        $element.attr("data-lastseen", $.now());
        change_avatar(worker_data, data_attribute);
        $element.data('slackname', worker_data.slack_name);
        $element.data('online', worker_data.online);

        data_attribute_worker = "[data-devicename='" + worker_data.device_name + "']";

        if ( $(data_attribute_worker).find(".tape").text() !== ( worker_data.name || sanitize_name(worker_data.device_name) ) ) {
          // if the tape (shown name) isn't right, we nuke now to add later
          // console.log("this is the problem");
          Worker.remove_worker(data_attribute_worker);
        }
      } else {
        // the worker wasn't there before.
        Worker.setup_and_add(worker_data);
        if (worker_data.name) {
          // removing the device version if it's there, keeping the name one.
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
        if (name_change == "") {
          name_change = "ANONYMOUS";
        }
        return name_change
  };

  var strip_at_symbol = function(slack_name){
    return slack_name.replace('@','');
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
    })
  }


  var change_avatar = function(user_param, data_attribute){
    var element = $(data_attribute).find('.avatar_container img')
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
  var options = {
    keys:['name','slackname'],
    distance: 5,
    threshold: 0.3
  };
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
// searching
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

