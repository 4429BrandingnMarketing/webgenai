#
#--
#
# $Id$
#
# webgen: a template based web page generator
# Copyright (C) 2004 Thomas Leitner
#
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU
# General Public License as published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
# even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with this program; if not,
# write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
#++
#

require 'webgen/node'
require 'webgen/plugins/tags/tags'

module Tags

  # Generates a menu. All page files for which the meta information +inMenu+ is set are displayed.
  # If you have one page in several languages, it is sufficient to add this meta information to only
  # one page file.
  #
  # The order in which the menu items are listed can be controlled via the meta information
  # +menuOrder+. By default the menu items are sorted by the file names.
  #
  # Tag parameters:
  # [<b>level</b>]
  #   The depth of the menu. A level of one only displays the top level menu files. A level of two
  #   also displays the menu files in the direct subdirectories and so on.
  class MenuTag < DefaultTag


    # Specialised node class for the menu.
    class MenuNode < Node

      def initialize( parent, node )
        super parent
        self['title'] = 'Menu: '+ node['title']
        self['isMenuNode'] = true
        self['virtual'] = true
        self['node'] = node
      end


      # Sorts recursively all children of the node depending on their order value.
      def sort
        self.children.sort! do |a,b| get_order_value( a ) <=> get_order_value( b ) end
        self.children.each do |child| child.sort if child.kind_of?( MenuNode ) && child['node'].kind_of?( FileHandlers::DirHandler::DirNode ) end
      end


      # Retrieves the order value for the specific node.
      def get_order_value( node )
        # be optimistic and try metainfo field first
        node = node['node'] if node.kind_of?( MenuNode )
        value = node['menuOrder'].to_s.to_i unless node['menuOrder'].nil?

        # find the first menuOrder entry in the page files
        node = node['indexFile'] if node.kind_of?( FileHandlers::DirHandler::DirNode )
        node = node.find do |child| child['menuOrder'].to_s.to_i != 0 end if node.kind_of?( FileHandlers::PagePlugin::PageNode )
        value ||= node['menuOrder'].to_s.to_i unless node.nil?

        # fallback value
        value ||= 0

        value
      end

    end


    plugin 'Menu Tag'
    summary 'Builds up a menu'
    depends_on 'Tags'

    add_param 'submenuTag', 'ul', 'The tag used for making sub menus.'
    add_param 'itemTag', 'li', 'The tag used for menu items.'
    add_param 'level', 1, \
    'Specifies how many levels the menu should have by default, ie. how deep it is. ' \
    'For example, if level = 3, then three levels are always shown at least.'
    add_param 'subtreeLevel', 3, \
    'Specifies how many levels should be shown for subtrees. The number specifies ' \
    'the maximum depth the menu will have.'
    add_param 'showCurrentSubtreeOnly', true, \
    'True if only the current subtree should be shown in the menu. If set to false, ' \
    'each subtree will be shown.'

    def initialize
      super
      register_tag( 'menu' )
    end

    def process_tag( tag, node, refNode )
      unless defined?( @menuTree )
        @menuTree = create_menu_tree( Node.root( node ), nil )
        unless @menuTree.nil?
          Webgen::Plugin['TreeWalker'].execute( @menuTree, Webgen::Plugin['DebugTreePrinter'] )
          @menuTree.sort
          Webgen::Plugin['TreeWalker'].execute( @menuTree, Webgen::Plugin['DebugTreePrinter'] )
        end
      end
      build_menu( node, @menuTree, 1 )
    end


    #######
    private
    #######


    def build_menu( srcNode, node, level )
      if node.nil? \
        || level > get_param( 'subtreeLevel' ) \
        || ( level > get_param( 'level' ) \
             && ( node['node'].level > srcNode.level \
                  || ( get_param( 'showCurrentSubtreeOnly' ) && !node['node'].in_subtree?( srcNode ) )
                  )
             )
        return ''
      end

      out = "<#{get_param( 'submenuTag' )}>"
      node.each do |child|
        if child.kind_of?( MenuNode )
          submenu = child['node'].kind_of?( FileHandlers::DirHandler::DirNode ) ? build_menu( srcNode, child, level + 1 ) : ''
          before, after = menu_entry( srcNode, child['node'] )
        else
          submenu = ''
          before, after = menu_entry( srcNode, child )
        end

        out << before
        out << submenu
        out << after
      end
      out << "</#{get_param( 'submenuTag' )}>"

      return out
    end


    def menu_entry( srcNode, node )
      langNode = node['processor'].get_lang_node( node, srcNode['lang'] )
      isDir = node.kind_of?( FileHandlers::DirHandler::DirNode )

      styles = []
      styles << 'webgen-submenu' if isDir
      styles << 'webgen-menuitem-selected' if langNode.recursive_value( 'dest' ) == srcNode.recursive_value( 'dest' )

      style = " class=\"#{styles.join(' ')}\"" if styles.length > 0
      link = langNode['processor'].get_html_link( langNode, srcNode, ( isDir ? langNode['directoryName'] || node['directoryName'] : langNode['title'] ) )

      itemTag = get_param( 'itemTag' )
      if styles.include?( 'webgen-submenu' )
        before = "<#{itemTag}#{style}>#{link}"
        after = "</#{itemTag}>"
      else
        before = "<#{itemTag}#{style}>#{link}</#{itemTag}>"
        after = ""
      end

      self.logger.debug { [before, after] }
      return before, after
    end


    def create_menu_tree( node, parent )
      menuNode = MenuNode.new( parent, node )

      node.each do |child|
        menu = create_menu_tree( child, menuNode )
        menuNode.add_child( menu ) unless menu.nil?
      end

      return menuNode.has_children? ? menuNode : ( put_node_in_menu?( node ) ? node : nil )
    end


    def put_node_in_menu?( node )
      inMenu = node['inMenu']
      inMenu ||=  node.parent && node.parent.kind_of?( FileHandlers::PagePlugin::PageNode ) &&
                  node.parent.find do |child| child['inMenu'] end
      inMenu &&= !node['virtual']
      inMenu
    end

  end

end
