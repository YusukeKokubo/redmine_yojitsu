# encoding: utf-8
require 'set'

class YojitsuController < ApplicationController
  unloadable
  include YojitsuHelper
  before_filter :setup, :only => [:show, :graph_code]

  GraphColours = ["#0066ff", "#006600", "#3366ff", 
                  "#336600", "#6666ff", "#666600", 
                  "#9966ff", "#cc66ff", "#cc6600"]

  def graph_code
    time_history_graph("time entries history", @project.time_entries, @total_rfp_hours)
  end

  def time_history_graph(title, src_time_entries, total_rfp_hours)
    title = Title.new(title)

    time_entries_line = Line.new
    time_entries_line.default_dot_style = Dot.new
    time_entries_line.text = l(:yjt_time_entry)
    time_entries_line.width = 4
    time_entries_line.dot_size = 5
    time_entries_line.colour = '#DFC329'

    rfp_hours_line = Line.new
    rfp_hours_line.default_dot_style = Dot.new
    rfp_hours_line.text = l(:yjt_rfp_hours)
    rfp_hours_line.width = 4
    rfp_hours_line.dot_size = 5
    rfp_hours_line.colour = '#cc3333'
    
    estimated_hours_line = Line.new
    estimated_hours_line.default_dot_style = Dot.new
    estimated_hours_line.text = l(:yjt_estimated_hours)
    estimated_hours_line.width = 4
    estimated_hours_line.dot_size = 5
    estimated_hours_line.colour = '#336600'

    if src_time_entries.empty?
      start_date = Date.new
      end_date   = Date.new
    else
      start_date = src_time_entries.min_by(&:spent_on).spent_on
      end_date   = src_time_entries.max_by(&:spent_on).spent_on
    end

    # 開始週～終了週までをつくる
    weeks = []
    start_week, end_week = start_date.cweek, end_date.cweek
    if start_week <= end_week
        start_week.upto(end_week) { |week| weeks << week }
    else
        start_week.upto(53) { |week| weeks << week }
        1.upto(end_week)    { |week| weeks << week }
    end

    # 週ごとに時間を計算する
    total_time_spent = 0.0
    total_estimated_hours = Set.new
    time_entries = []
    rfp_hours = []
    estimated_hours = []
    labels = []
    weeks.each do |week|
        ts = src_time_entries.select { |t| t.spent_on.cweek == week }
        total_time_spent += ts.map(&:hours).inject(:+) || 0.0
        ts.each do |time_entry|
          next unless time_entry.issue
          next unless time_entry.issue.leaf?
          next unless time_entry.issue.estimated_hours
          total_estimated_hours << time_entry.issue
        end
        time_entries << total_time_spent
        estimated_hours << total_estimated_hours.map(&:estimated_hours).compact.inject(:+) || 0.0
        rfp_hours << total_rfp_hours # 見積もり時間は固定

        if ts.empty?
          labels << "-"
        else
          labels << ts.max_by(&:spent_on).spent_on.strftime("%m / %d")
        end
    end
    time_entries_line.values = time_entries
    rfp_hours_line.values = rfp_hours
    estimated_hours_line.values = estimated_hours

    x_labels = XAxisLabels.new(:rotate => 60)
    x_labels.labels = labels
    x = XAxis.new
    x.set_labels(x_labels)

    y = YAxis.new
    y_max = [total_time_spent, total_rfp_hours].max + 20
    y_step = case y_max
           when 0..100
               y_step = 10
           when 100..500
               y_step = 50
           when 500..1500
               y_step = 100
           else
               y_step = 200
           end
    y.set_range(0, y_max, y_step)

    chart = OpenFlashChart.new
    chart.set_title(title)
    chart.y_axis = y
    chart.x_axis = x
    chart.add_element(rfp_hours_line)
    chart.add_element(estimated_hours_line)
    chart.add_element(time_entries_line)
    render :text => chart.to_s
  end

  def trackertime
    @project = Project.find(params[:id])
    pie = Pie.new
    pie.colours = GraphColours

    @time_entries = {}
    nilTracker = Tracker.new(:name => "Trackerなし")
    @project.time_entries.each do |te|
      issue = te.issue
      tracker = issue.is_task? ? (issue.parent ? issue.parent.tracker : nilTracker) : issue.tracker
      @time_entries[tracker] ||= 0
      @time_entries[tracker] += te.hours
    end

    pie.values = @time_entries.map{|name, hour| PieValue.new(hour, "#{name}")}
    chart = OpenFlashChart.new
    chart.set_title(Title.new("Tracker"))
    chart.add_element(pie)
    render :text => chart.to_s
  end

  def activitytime
    @project = Project.find(params[:id])
    pie = Pie.new
    pie.colours = GraphColours

    @spent_hours = {}
    @project.time_entries \
              .group_by{|te| te.activity.name} \
              .each{|n, tes| @spent_hours[n] = tes.map(&:hours).inject(:+)}

    pie.values = @spent_hours.map{|name, hour| PieValue.new(hour, "#{name}")}
    chart = OpenFlashChart.new
    chart.set_title(Title.new("Activity"))
    chart.add_element(pie)
    render :text => chart.to_s
  end

  def assignee
    @user = User.find(params[:user_id])
    @project = Project.find(params[:id])
    spent_time = @project.time_entries\
                    .select{|te|te.user == @user and te.issue.assigned_to == @user and te.issue.closed?}\
                    .map(&:hours).inject(:+) || 0
    estimated_time = @project.issues\
                    .select{|is| is.assigned_to == @user and is.closed?}\
                    .select(&:leaf?)\
                    .map(&:estimated_hours).compact.inject(:+) || 0.0
    remain = estimated_time - spent_time
    bar = Bar.new
    bar.colour = remain > 0 ? "#0000ff" : "#ff0000"
    bar.values = [remain]
    chart = OpenFlashChart.new
    chart.set_title(Title.new("#{@user.name} \n #{l(:field_estimated_hours)}:#{l_hour(estimated_time)} \n #{l(:field_spent_hours)}:#{l_hour(spent_time)}"))
    chart.add_element(bar)
    y_axis = YAxis.new
    limit = remain.abs
    step = case limit
           when 0..10
             1
           when 10..120
             10
           else
             50
           end
    y_axis.set_range(0 - (limit + step), limit + step, step)
    chart.set_y_axis(y_axis)

    render :text => chart.to_s
  end

  def personal
    @user = User.find(params[:user_id])
    @project = Project.find(params[:id])
    time_entries = @project.time_entries.select {|ts| ts.user == @user}
    personal_estimated_tracker = Tracker.find(50)
    cf = CustomField.find(22)
    issue = @project.issues.detect {|i| i.tracker == personal_estimated_tracker and i.assigned_to == @user}
    rfp_hours = cf.cast_value(issue.custom_values.detect {|cv|cv.custom_field_id==cf.id}.value)
    time_history_graph(@user.name, time_entries, rfp_hours)
  end

  def show
    @trackertime = open_flash_chart_object(300, 200, url_for(:action => 'trackertime', :id => params[:id]))
    @activitytime = open_flash_chart_object(300, 200, url_for(:action => 'activitytime', :id => params[:id]))
    @graph = open_flash_chart_object(900, 600, url_for(:action => 'graph_code', :id => params[:id]))

    @usertimes = @project.issues \
      .map(&:assigned_to).compact.uniq.sort \
      .map {|u| open_flash_chart_object(150, 350, url_for(:action => 'assignee', :id => params[:id], :user_id => u.id))}

    personal_estimated_tracker = Tracker.find(50)
    @personal_estimated_hours = @project.issues \
      .select {|i| i.tracker == personal_estimated_tracker} \
      .sort_by(&:assigned_to) \
      .map {|i| open_flash_chart_object(350, 300, url_for(:action => 'personal', :id => params[:id], :user_id => i.assigned_to.id))}
    
    @category_time_entries = {}
    @category_estimated_hours = {}
    @tracker_time_entries = {}
    @tracker_estimated_hours = {}
    @activities_spent_hours = {}
    @custom_spent_hours = {}
    nilCategory = IssueCategory.new(:name => "カテゴリなし")
    nilTracker = Tracker.new(:name => "Trackerなし")

    @project.time_entries.each do |te|
      issue = te.issue
      category = issue.category || nilCategory
      @category_time_entries[category] ||= 0
      @category_time_entries[category] += te.hours if te.hours

      tracker = issue.is_task? ? (issue.parent ? issue.parent.tracker : nilTracker) : issue.tracker
      @tracker_time_entries[tracker] ||= 0
      @tracker_time_entries[tracker] += te.hours

      @activities_spent_hours[te.activity.name] ||= 0
      @activities_spent_hours[te.activity.name] += te.hours
      te.custom_values.each do |v|
        @custom_spent_hours[v.custom_field.name] ||= {}
        @custom_spent_hours[v.custom_field.name][v.value] ||= 0
        @custom_spent_hours[v.custom_field.name][v.value] += te.hours
      end
    end

    @project.issues.each do |issue|
      next unless issue.leaf?
      category = issue.category || nilCategory
      @category_estimated_hours[category] ||= 0
      @category_estimated_hours[category] += issue.estimated_hours if issue.estimated_hours
      tracker = issue.is_task? ? (issue.parent ? issue.parent.tracker : nilTracker) : issue.tracker
      @tracker_estimated_hours[tracker] ||= 0
      @tracker_estimated_hours[tracker] += issue.estimated_hours if issue.estimated_hours
    end
    @problem_issues = Issue.find(:all,
                                 :conditions => ["project_id = ? and tracker_id = ?", @project.id, 38])

    @thinkback_issues = @project.issues.select {|i| i.custom_values[0] and i.custom_values[0].value == "1"}
  end

  private
  def setup
    @project = Project.find(params[:id])

    # Sprints
    # ※BacklogsプラグインのSprintは将来的にVersionと同一視されなくなるので注意
    @sprints = RbSprint.find(:all, 
                           :order => 'sprint_start_date ASC, effective_date ASC',
                           :conditions => ["project_id = ?", @project.id])

    # rfp hours
    @total_rfp_hours = @project.custom_values[0] ? @project.custom_values[0].to_s.to_f : 0.0

    @total_estimated_hours = @project.issues.select(&:leaf?).map(&:estimated_hours).compact.inject(:+) || 0.0

    @total_spent_hours = @project.time_entries.map(&:hours).inject(:+) || 0.0

    @backlog = RbStory.product_backlog(@project)
    @issue_trackers = @project.trackers.all.delete_if {|t| t.id == RbTask.tracker or RbStory.trackers.include?(t.id) }
    @issues = RbStory.find(
                     :all, 
                     :conditions => ["project_id=? AND tracker_id in (?)", @project, @issue_trackers],
                     :order => "position ASC"
                    )
  end
end
