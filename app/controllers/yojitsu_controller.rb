require 'set'

class YojitsuController < ApplicationController
  unloadable
  before_filter :setup, :except => :usertime

  def graph_code
    title = Title.new("time entries history.")

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

    start_date = @project.time_entries.minimum('spent_on').to_date
    end_date   = @project.time_entries.maximum('spent_on').to_date

    # 開始週～終了週までをつくる
    @weeks = []
    start_week, end_week = start_date.cweek, end_date.cweek
    if start_week <= end_week
        start_week.upto(end_week) { |week| @weeks << week }
    else
        start_week.upto(53) { |week| @weeks << week }
        1.upto(end_week)    { |week| @weeks << week }
    end

    # 週ごとに時間を計算する
    total_time_spent = 0.0
    total_estimated_hours = Set.new
    time_entries = []
    rfp_hours = []
    estimated_hours = []
    labels = []
    @weeks.each do |week|
        ts = @project.time_entries.select { |t| t.spent_on.cweek == week }
        total_time_spent += ts.inject(0.0) {|sum, t| sum + t.hours}
        ts.each do |time_entry|
          next unless time_entry.issue
          next unless time_entry.issue.leaf?
          next unless time_entry.issue.estimated_hours
          total_estimated_hours << time_entry.issue
        end
        time_entries << total_time_spent
        estimated_hours << total_estimated_hours.inject(0.0) {|sum, i| sum + i.estimated_hours}
        rfp_hours << @total_rfp_hours # 見積もり時間は固定

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
    y_max = [total_time_spent, @total_rfp_hours].max + 20
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

    x_legend = XLegend.new("days")
    x_legend.set_style('{font-size: 20px; color: #778877}')

    y_legend = YLegend.new("hours")
    y_legend.set_style('{font-size: 20px; color: #770077}')

    chart = OpenFlashChart.new
    chart.set_title(title)
    chart.set_x_legend(x_legend)
    chart.set_y_legend(y_legend)
    chart.y_axis = y
    chart.x_axis = x
    chart.add_element(rfp_hours_line)
    chart.add_element(estimated_hours_line)
    chart.add_element(time_entries_line)
    render :text => chart.to_s
  end

  def usertime
    @user = User.find(params[:user_id])
    @project = Project.find(params[:id])
    pie = Pie.new
    pie.colours = ["#0000ff", "#006600"]
    issues = @project.issues.select {|is| is.assigned_to == @user}
    spent_time = issues.map {|i| i.time_entries.select {|ts| ts.user == @user}}.flatten.inject(0.0) {|sum, ts| sum += ts.hours}
    estimated_time = issues.inject(0.0) {|sum, i| i.estimated_hours ? sum += i.estimated_hours : sum}
    remain = estimated_time - spent_time
    pie.values = [PieValue.new(spent_time, "#{l(:field_time_entry_hours)}:#{spent_time}"), 
                  PieValue.new(remain > 0 ? remain : 0, "#{l(:label_hours_remaining)}:#{remain}")]
    chart = OpenFlashChart.new
    chart.set_title(Title.new("#{@user.name} (#{l(:field_estimated_hours)}:#{estimated_time})"))
    chart.add_element(pie)
    render :text => chart.to_s
  end

  def show
    @graph = open_flash_chart_object(900, 600, "/yojitsu/graph_code/#{params[:id]}")
    @usertimes = @project.members \
      .select {|u| @project.time_entries.map(&:user).include? u.user} \
      .map {|u| open_flash_chart_object(300, 200, "/yojitsu/usertime/#{params[:id]}/#{u.user.id}")}
    
    @category_time_entries = {}
    @category_estimated_hours = {}
    @tracker_time_entries = {}
    @tracker_estimated_hours = {}
    @activities_spent_hours = {}
    @custom_spent_hours = {}
    nilCategory = IssueCategory.new(:name => "カテゴリなし")
    nilTracker = Tracker.new(:name => "Trackerなし")
    @project.issues.each do |issue|
      next unless issue.leaf?
      category = issue.category || nilCategory
      @category_estimated_hours[category] ||= 0
      @category_estimated_hours[category] += issue.estimated_hours if issue.estimated_hours
      @category_time_entries[category] ||= 0
      @category_time_entries[category] += issue.spent_hours if issue.spent_hours
      tracker = issue.is_task? ? (issue.parent ? issue.parent.tracker : nilTracker) : issue.tracker
      @tracker_time_entries[tracker] ||= 0
      @tracker_time_entries[tracker] += issue.spent_hours
      @tracker_estimated_hours[tracker] ||= 0
      @tracker_estimated_hours[tracker] += issue.estimated_hours if issue.estimated_hours

      issue.time_entries.each do |ts|
        @activities_spent_hours[ts.activity.name] ||= 0
        @activities_spent_hours[ts.activity.name] += ts.hours
        ts.custom_values.each do |v|
          @custom_spent_hours[v.custom_field.name] ||= {}
          @custom_spent_hours[v.custom_field.name][v.value] ||= 0
          @custom_spent_hours[v.custom_field.name][v.value] += ts.hours
        end
      end
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

    @total_estimated_hours = 0.0
    @total_spent_hours = 0.0
    @project.issues.each do |i|
      next unless i.leaf?
      @total_estimated_hours += i.estimated_hours if i.estimated_hours
      @total_spent_hours += i.spent_hours if i.spent_hours
    end
    @backlog = RbStory.product_backlog(@project)
    @issue_trackers = @project.trackers.all.delete_if {|t| t.id == RbTask.tracker or RbStory.trackers.include?(t.id) }
    @issues = RbStory.find(
                     :all, 
                     :conditions => ["project_id=? AND tracker_id in (?)", @project, @issue_trackers],
                     :order => "position ASC"
                    )
  end
end
