# encoding: utf-8

module RubyProf
  class CallInfo
    # part of this class is defined in C code.
    # it provides the following attributes pertaining to tree structure:
    # depth:      tree level (0 == root)
    # parent:     parent call info (can be nil)
    # children:   array of call info children (can be empty)
    # target:     method info (containing an array of call infos)

    def measure_values_memoized
      @measure_values ||= measure_values
    end

    def total_time(i = 0)
      measure_values_memoized[i][0]
    end

    def self_time(i = 0)
      measure_values_memoized[i][1]
    end

    def wait_time(i = 0)
      measure_values_memoized[i][2]
    end

    def children_time(i = 0)
      children.inject(0) do |sum, call_info|
        sum += call_info.total_time(i)
      end
    end

    def stack
      @stack ||= begin
        methods = Array.new
        call_info = self

        while call_info
          methods << call_info.target
          call_info = call_info.parent
        end
        methods.reverse
      end
    end

    def call_sequence
      @call_sequence ||= begin
        stack.map {|method| method.full_name}.join('->')
      end
    end

    def root?
      self.parent.nil?
    end

    def descendent_of(other)
      p = self.parent
      while p && p != other && p.depth > other.depth
        p = p.parent
      end
      p == other
    end

    def self.roots_of(call_infos)
      roots = []
      sorted = call_infos.sort_by(&:depth).reverse
      while call_info = sorted.shift
        roots << call_info unless sorted.any?{|p| call_info.descendent_of(p)}
      end
      roots
    end

    def to_s
      "#{target.full_name} (c: #{called}, tt: #{total_time}, st: #{self_time}, ct: #{children_time})"
    end

    def inspect
      super + "(#{target.full_name}, d: #{depth}, c: #{called}, tt: #{total_time}, st: #{self_time}, ct: #{children_time})"
    end

    # find a specific call in list of children. returns nil if not found.
    # note: there can't be more than one child with a given target method. in other words:
    # x.children.grep{|y|y.target==m}.size <= 1 for all method infos m and call infos x
    def find_call(other)
      matching = children.select { |kid| kid.target == other.target }
      raise "inconsistent call tree" unless matching.size <= 1
      matching.first
    end

    # merge two call trees. adds self, wait, and total time of other to self and merges children of other into children of self.
    def merge_call_tree(other)
      # $stderr.puts "merging #{self}\nand #{other}"
      self.called += other.called
      add_self_time(other)
      add_wait_time(other)
      add_total_time(other)
      other.children.each do |other_kid|
        if kid = find_call(other_kid)
          # $stderr.puts "merging kids"
          kid.merge_call_tree(other_kid)
        else
          other_kid.parent = self
          children << other_kid
        end
      end
      other.children.clear
      other.target.call_infos.delete(other)
    end
  end
end
