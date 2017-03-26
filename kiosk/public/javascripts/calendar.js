$(document).ready(function() {

  window.setInterval(function() {
    // get the events from google every 15 seconds
    $('#calendar').fullCalendar('refetchEvents')
  }, 15000);

  window.setInterval(function(){
    // every hour refresh the page
    // for the reception kiosk
    window.location.href = window.location.href;
  },1000 * 60 * 60);

  // should probably use
  // http://stackoverflow.com/questions/4644027/how-to-automatically-reload-a-page-after-a-given-period-of-inactivity

  // zero out the modal on hide
  $("#fullCalModal").on('hidden.bs.modal', function() {
    $(this).data('bs.modal', null);
  });

  var isMobile = window.matchMedia("only screen and (max-width: 760px)");
  var me = {};

  $.ajax({
    url: '/me',
    dataType: 'json',
    cache: true
  }).done(function(d) {
    me = d['data'];
  }).fail(function() {
    me = {
      real_name: ""
    };
    console.log('send to register');
    //window.location.href='/register'
  });

  $('#calendar').fullCalendar({
    customButtons: {
      people: {
        text: 'Back to The People',
        click: function() {
          window.location = '/';
        }
      }
    },
    header: {
      left: 'prev,next today',
      center: 'title people',
      right: 'agendaWeek,agendaDay'
    },
    defaultView: 'agendaDay',
    defaultDate: moment().tz('America/New_York'),
    scrollTime: '09:00:00', // undo default 6am scrollTime
    eventLimit: true,
    nowIndicator: true,
    eventOverlap: false,
    timezone: 'America/New_York',
    slotEventOverlap: false,
    allDaySlot: false,
    schedulerLicenseKey: 'CC-Attribution-NonCommercial-NoDerivatives',
    groupByResource: true,
    editable: true,
    selectable: true,
    selectHelper: true,
    slotDuration: '00:15:00',
    minTime: '08:00:00',
    eventClick: function(event, jsEvent, view) {
      $('#modalEventId').val(event.id);
      $('#modalTitle').html(event.title);
      $('#modalStart').html(event.start.format("dd, Do h:mm a"));
      $('#modalEnd').html(event.end.format("dd, Do h:mm a"));
      $('#modalCalendar').val(event.resourceId);
      $('#eventUrl').attr('href', event.url);
      $('#modalDelete').data('event_id', event.id);
      $('#modalDelete').data('calendar', event.resourceId);
      $('#fullCalModal').modal();

      jsEvent.preventDefault();

      $('#modalDelete').one('click', function(el) {
        var $el = $(this);
        $('#fullCalModal').modal('hide');
        var event_id = $el.data('event_id');
        var calendar = $el.data('calendar');
        var obj = {
          id: event_id,
          calendar: calendar
        }

        $.ajax({
          type: 'DELETE',
          cache: false,
          url: '/calendar',
          dataType: 'json',
          data: obj
        }).done(function(d) {
          $('#calendar').fullCalendar('removeEvents', event_id);
        }).fail(function(d) {
          alert('error:' + d.msg);
        });
      })
    },
    // user selects times on the calendar for a new event
    select: function(start, end, event, view, res) {
      $('#calendar').fullCalendar('renderEvent', {
          id: event.id,
          title: event.resourceId + " - " + me.real_name,
          start: moment(start).tz('America/New_York').format(),
          end: moment(end).tz('America/New_York').format(),
          resourceId: event.resourceId,
          className: 'loading'
        },
        false
      );
      resource_select(start.format(), end.format(), res);
    },
    eventDrop: function(event, delta, revertFunc, jsEvent, ui, view) {
      // delta is the change in milliseconds to the start and end of the event.
      console.log('dropped')
      var id = event.id;
      var start = event.start.format();
      var end = event.end.format();
      var calendar = event.resourceId;

      if (event.title.indexOf("#>") != -1) {
        event.title = event.title.split('#>')[1];
      }

      event.title = calendar + " - " + me.real_name + '#>' + event.title;
      event.color = resourceId2color(calendar);
      event.className = 'loading';

      var url = "/calendar";
      var data = {
        'id': id,
        'title': event.title,
        'start': start,
        'end': end,
        'calendar': calendar
      };

      $.post(url, data).done(function() {
        setTimeout($('#calendar').fullCalendar('refetchEvents'), 500);
      }).fail(function() {
        console.log('in fail!');
        refertFunc();
      });
    },
    eventResize: function(event, delta, revertFunc, jsEvent, ui, view) {
      // delta is the change in milliseconds to the end of the event.
      // get event id, send new times to backend
      // on success refresh calendar events
      // on fail call refertFunc.
      var id = event.id;
      var start = event.start.format();
      var end = event.end.format();
      var calendar = event.resourceId;
      var title = event.title;

      save_event_gcal(id, title, start, end, calendar, revertFunc);
    },
    googleCalendarApiKey: 'AIzaSyAOzgZPmbbgrd79XHDyWu9oyhmcJaVfXv8',
    resources: [{
        id: 'tiny',
        title: 'Tiny'
      },
      {
        id: 'smalls',
        title: 'Smalls'
      },
      {
        id: 'biggie',
        title: 'Biggie'
      }
    ],
    eventSources: [{
        googleCalendarId: 'robinhood.org_2d37313337333130363239@resource.calendar.google.com',
        className: 'tiny',
        color: 'green',
        resourceId: 'tiny',
        editable: true
      },
      {
        googleCalendarId: 'robinhood.org_3730373137363538363534@resource.calendar.google.com',
        className: 'smalls',
        color: 'red',
        resourceId: 'smalls',
        editable: true
      }, {
        googleCalendarId: 'robinhood.org_2d33313439373439322d363134@resource.calendar.google.com',
        className: 'biggie',
        color: 'blue',
        resourceId: 'biggie',
        editable: true
      }
    ],
    eventRender: function(event, element) {
      if (typeof(event.source) != 'undefined' && typeof(event.source.className) != 'undefined') {
        element.find('.fc-time').append('<div class="h5 title pull-right" >' + event.source.className + '</div>');
      }
    }
  });

  function resource_select(start, end, res) {
    var e_id = uuid();
    var calendar = res.id;
    var title = res.id + " - " + me.real_name;
    save_event_gcal(e_id, title, start, end, calendar);
  }

  // saves the event, revert on fail.
  function save_event_gcal(id, title, start, end, calendar, revertFunc) {
    var url = "/calendar";
    var data = {
      'id': id,
      'title': title,
      'start': start,
      'end': end,
      'calendar': calendar
    };

    $.post(url, data).done(function(d) {
      console.log('rendering event.');

      $('#calendar').fullCalendar('unselect');

      $('#calendar').fullCalendar('renderEvent', {
          id: id,
          title: title,
          start: start,
          end: end,
          className: 'loading',
          resourceId: calendar,
          color: resourceId2color(calendar)
        },
        false
      );
    }).fail(function(d) {
      console.log(d);
      if ($.isFunction(revertFunc)) {
        alert('could not save event')
        revertFunc();
      }
    });

    setTimeout($('#calendar').fullCalendar('refetchEvents'), 500);
  }

  function uuid() {
    // 128 character random string. Should literally never collide.
    var uuid = "",
      i, random;
    for (i = 0; i < 128; i++) {
      random = Math.random() * 16 | 0;
      uuid += (i == 12 ? 4 : (i == 16 ? (random & 3 | 8) : random)).toString(16);
    }
    return uuid;
  }

  function resourceId2color(res) {
    obj = {
      'biggie': 'blue',
      'tiny': 'green',
      'smalls': 'red'
    };
    return obj[res];
  }
  // touch screen!!
  var isTouchDevice = 'ontouchstart' in document.documentElement;

  if (isTouchDevice) {
    $("#calendar").swipe({
      tap: function(event, target) {
        $(target).click();
      },
      doubleTap: function(event, target) {
        $(target).click();
      },
      longTap: function(event, target) {
        $(target).click();
      },
      swipe: function(event, direction, distance, duration, fingerCount, fingerData) {
        if (direction == 'right') {
          $('#calendar').fullCalendar('prev');
        }
        if (direction == 'left') {
          $('#calendar').fullCalendar('next');
        }
      },
      threshold: 50,
      fingers: 'all',
      allowPageScroll: "vertical"
    });
  }
});
