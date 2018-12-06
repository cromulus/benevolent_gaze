$(function() {
$('.form-control-clear').click(function() {
    $(this).siblings('input[type="text"]').val('').trigger('propertychange').focus();
    $('.form-control-clear button').removeClass('btn-primary').addClass('btn-secondary');
    $(this).siblings('input[type="text"]').blur();
    $('.worker').each(function(i, v) { $(v).show(); });
  });

  // searches for workers. simple Fuse search.
  var filter = function() {
    // map through each worker, hide it, and return a searchable obj.
    var searchable_workers = $('.worker').map(function() {
          $(this).hide(); // hide em all.
          return { name: $(this).data('name'), title:$(this).data('title'), obj: $(this)}
        })

    // we search only name, could possibly search slackname or device...
    // should be "fuzzy" enough to be usefull
    var options = {
      keys: ['name', 'title'],
      distance: 30,
      threshold: 0.3
    };

    var fuse = new Fuse(searchable_workers, options);
    var query = $('input').val();
    var found = [];
    if (query.length > 0) {
      found = fuse.search(query);
      // show only found workers.
      $(found).each(function(i, v) { $(v.obj).show();});
    } else {
      // show all of the workers, didn't find anything
      $('.worker').each(function(i, v) { $(v).show(); });
    }
  };
  // should we think about a typeahead +filter here? for ease of use?
  // similar to register.js for slack ids, would need to ajax.
  // searching, simple debounce
  var t = null;
  $('input').keyup(function() {
      if (t) {
          clearTimeout(t);
      }
      t = setTimeout(filter(), 100);
      if ($('input').val() != '') {
        $('.form-control-clear button').removeClass('btn-secondary').addClass('btn-primary');
      } else {
        $('.form-control-clear button').removeClass('btn-primary').addClass('btn-secondary');
      }
  });
});
