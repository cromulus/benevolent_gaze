$(function() {

  window.setInterval(function(){
    // every hour refresh the page
    // for the reception kiosk
    window.location.href = window.location.href;
  },1000 * 60 * 60);
  // should probably use
  // http://stackoverflow.com/questions/4644027/how-to-automatically-reload-a-page-after-a-given-period-of-inactivity




  // sends the user to register if unregistered,
  // otherwise, sets up the reception kiosk keyboard
  // should probably be a standalone "user" script/object
  // duplicates alof of the functionality of the ""
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
        window.location.href='/register'
      }
    }
  });


  var es = new EventSource('/feed');
  var people = [];

  es.addEventListener('error', function(e) {
    if (e.readyState == EventSource.CLOSED) {
      console.log('closed'); // not sure what to do here.
      // maybe refresh the page anyway?
      setTimeout(window.location.href='/', 500);; // reload page on error
    }else{
      setTimeout(window.location.href='/register', 500);; // reload page on error
    }
  }, false);

  es.addEventListener('message', function(e) {
    data = JSON.parse(e.data); //
    // evveryone from the feed
    people = jQuery.grep( data, function(d){
      return d.type === 'device'});

    // any messages we might have received
    msgs = jQuery.grep( data, function(d){return d.type === 'msg'});

    // loop through messages and send them to workers.
    msgs.forEach(onmessage);

    // add new workers to the board.
    add_remove_workers(people);

    // check to see if any are stale
    // stale == not in feed for a little while.
    check_last_seen();
  }, false);

  es.addEventListener('open', function(e) {
    console.log('Connection was opened.');
  }, false);

  // handles inbound messages
  // should refactor most of this into Worker class
  var onmessage = function(msg) {
    console.log(msg);

    var slack_name = msg['user'].replace('@','');
    var old_content = '';
    $worker = $('[data-slackname='+slack_name+']')
    if ($worker.data('bs.popover') !== 'undefined') {
      old_content = $worker.data('bs.popover').options.content + "<br>";

    }

    $worker.popover('destroy');

    var options = {
      title : "<span class='text-info'><strong>Message</strong></span>"+
                '<button type="button" class="close" >&times;</button>',
      content: old_content + msg['msg'],
      trigger: 'manual',
      placement: 'auto',
      html: true
    }


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
    $worker.find('button.close').on('click',function(e){
      $worker.popover('destroy');
    });
  }


  // stores the worker we are currently operating on.
  var w; // I don't like it. seems like it could be prone to race conditions.
  // how do we deal with this?

  // the main worker management code is below.
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
                    $(this).next('.popover').find('button.cancel').click(function (e) {
                      $pop.popover('destroy');
                    });

                    setTimeout(function () {
                      $pop.popover('destroy');
                    }, 1000 * 7); // seven second timeout
                  });
                },
    add_class: function(device_name){
                 w.addClass(device_name.replace(/\./g, ""));
               },
    add_to_board: function(worker_data){
                    Worker.add_slack();
                    //Welcome.move_logo_and_welcomes();
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

  // how much of the below should be in Worker?
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
      // if we haven't seen the worker in the feed for 15 seconds, drop it.
      if (parseInt($(wk).attr('data-lastseen')) < ($.now() - 1000 * 15) && $(wk).find('.tape').text() !== "Ted" ) {
        // console.log("inside if");
        Worker.remove_worker(wk);
      }
    })
    Worker.redraw();
  }


  var change_avatar = function(user_param, data_attribute){
    var element = $(data_attribute).find('.avatar_container img')
    if (typeof user_param.avatar == "string" && user_param.avatar != element.attr('src')) {
      $(data_attribute).find(".avatar_container img").attr('src',user_param.avatar);
    }
  };


  // searches for workers. simple Fuse search.
  var filter = function(){
    // map through each worker, hide it, and return a searchable obj.
    var searchable_workers = $('.worker').map(function(){
          $(this).hide(); // hide em all.
          return { name: $(this).data('name'), obj: $(this)}
        })

    // we search only name, could possibly search slackname or device...
    // should be "fuzzy" enough to be usefull
    var options = {
      keys:['name'],
      distance: 5,
      threshold: 0.3
    };

    var fuse = new Fuse(searchable_workers,options);
    var query = $("input").val();
    var found = [];
    if (query.length>0) {
      found = fuse.search(query);
      // show only found workers.
      $(found).each(function(i,v){$(v.obj).show();});
    }else{
      // show all of the workers, didn't find anything
      $('.worker').each(function(i,v){$(v).show();});
    }
  }
  // should we think about a typeahead +filter here? for ease of use?
  // similar to register.js for slack ids, would need to ajax.
  // searching, simple debounce
  var t = null;
  $("input").keyup(function(){
      if (t) {
          clearTimeout(t);
      }
      t = setTimeout(filter(), 100);
  });

});

