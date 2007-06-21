# The BSD License
#
# Copyright (c) 2004-2007, George K. Moschovitis. (http://www.gmosx.com)
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# * Neither the name of Nitro nor the names of its contributors may be
# used to endorse or promote products derived from this software
# without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#

module Ramaze

# Displays a collection of entitities in multiple pages.
#
# === Design
#
# This pager is carefully designed for scaleability. It stores
# only the items for one page. The key parameter is needed,
# multiple pagers can coexist in a single page. The pager
# leverages the SQL LIMIT option to optimize database
# interaction.

class Pager
  include Ramaze::LinkHelper

  # Items per page.

  trait :limit => 10

  # The request key.

  trait :key => '_page'

  # The current page.

  attr_accessor :page

  # Items per page.

  attr_accessor :limit

  # The total number of pages.

  attr_accessor :page_count

  # Total count of items.

  attr_accessor :total_count

  def initialize(request, limit, total_count, key = trait[:key])
    raise 'limit should be > 0' unless limit > 0

    @request, @key = request, key
    @page = (request.params[key] || 1).to_i
    @limit = limit
    set_count(total_count)
    @start_idx = (@page - 1) * limit
  end

  def set_count(total_count)
    @total_count = total_count
    @page_count = (@total_count.to_f / @limit).ceil
  end

  # Return the first page index.

  def first_page
    1
  end

  # Is the first page displayed?

  def first_page?
    @page == 1
  end

  # Return the last page index.

  def last_page
    return @page_count
  end

  # Is the last page displayed?

  def last_page?
    @page == @page_count
  end

  # Return the index of the previous page.

  def previous_page
    [@page - 1, 1].max
  end

  # Return the index of the next page.

  def next_page
    [@page + 1, @page_count].min
  end

  # A set of helpers to create links to common pages.

  for target in [:first, :last, :previous, :next]
    eval %{
      def link_#{target}_page
        target_uri(#{target}_page)
      end
      alias_method :#{target}_page_uri, :link_#{target}_page
      alias_method :#{target}_page_href, :link_#{target}_page
    }
  end

  # Iterator

  def each(&block)
    @page_items.each(&block)
  end

  # Iterator
  # Returns 1-based index.

  def each_with_index
    idx = @start_idx
    for item in @page_items
      yield(idx + 1, item)
      idx += 1
    end
  end

  # Is the pager empty, ie has one page only?

  def empty?
    @page_count < 1
  end

  # The items count.

  def size
    @total_count
  end

  # Returns the range of the current page.

  def page_range
    s = @idx
    e = [@idx + @items_limit - 1, all_total_count].min

    return [s, e]
  end

  # Override if needed.

  def nav_range
    # effective range = 10 pages.
    s = [@page - 5, 1].max
    e = [@page + 9, @page_count].min

    d = 9 - (e - s)
    e += d if d < 0

    return (s..e)
  end

  # To be used with Og queries.

  def limit
    if @start_idx > 0
      { :limit => @limit, :offset => @start_idx }
    else
      { :limit => @limit }
    end
  end

  def offset
    @start_idx
  end

  # Override this method in your application if needed.
  #--
  # TODO: better markup.
  #++

  def navigation
    nav = ""

    unless first_page?
      nav << %{
        <div class="first"><a href="#{first_page_href}">First</a></div>
        <div class="previous"><a href="#{previous_page_href}">Previous</a></div>
      }
    end

    unless last_page?
      nav << %{
        <div class="last"><a href="#{last_page_href}">Last</a></div>
        <div class="next"><a href="#{next_page_href}">Next</a></div>
      }
    end

    nav << %{<ul>}

    for i in nav_range()
      if i == @page
        nav << %{
          <li class="active">#{i}</li>
        }
      else
        nav << %{
          <li><a href="#{target_uri(i)}">#{i}</a></li>
        }
      end
    end

    nav << %{</ul>}

    return nav
  end

  def navigation?
    @page_count > 1
  end

private

  # Generate the target URI.

  def target_uri(page)
    params = Request.current.params.dup.update(@key => page)
    Rs(Action.current.method, params)
  end

end

# Pager related helper methods.

module PagerHelper

private

  # Helper method that generates a collection of items and the
  # associated pager object.
  #
  # === Example
  #
  # entries, pager = paginate(Article, :where => 'title LIKE..', :limit => 10)
  #
  # or
  #
  # items = [ 'item1', 'item2', ... ]
  # entries, pager = paginate(items, :limit => 10)
  #
  # or
  #
  # entries, pager = paginate(article.comments, :limit => 10)
  #
  # <ul>
  # <?r for entry in entries ?>
  #    <li>#{entry.to_link}</li>
  # <?r end ?>
  # </ul>
  # #{pager.navigation}

  def paginate(items, options = {})
    limit = options.delete(:limit) || options[:limit] || Pager.trait[:limit]
    pager_key = options.delete(:pager_key) || Pager.trait[:key]

    case items
      when Array
        pager = Pager.new(request, limit, items.size, pager_key)
        items = items.slice(pager.offset, pager.limit[:limit])
        return items, pager
    end

    if defined?(Og)
      case items
      when Og::Collection
        pager = Pager.new(request, limit, items.count, pager_key)
        options.update(pager.limit)
        items = items.reload(options)
        return items, pager

      when Og::Mixin
        pager = Pager.new(request, limit, items.count(options), pager_key)
        options.update(pager.limit)
        items = items.all(options)
        return items, pager
      end
    end
  end

end

end
