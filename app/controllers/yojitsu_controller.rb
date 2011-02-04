class YojitsuController < ApplicationController
  unloadable
  before_filter :setup

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

    total = 0
    time_entries = []
    rfp_hours = []
    estimated_hours = []
    labels = []
    start_date = @project.time_entries.minimum('spent_on').to_date
    end_date   = @project.time_entries.maximum('spent_on').to_date

    @weeks = []
    start_week, end_week = start_date.cweek, end_date.cweek
    if start_week <= end_week
        start_week.upto(end_week) { |week| @weeks << week }
    else
        start_week.upto(53) { |week| @weeks << week }
        1.upto(end_week)    { |week| @weeks << week }
    end

    @weeks.each do |week|
        ts = @project.time_entries.select do |t|
            t.spent_on.cweek == week
        end
        total += ts.inject(0.0) {|sum, t| sum += t.hours}
        time_entries << total
        rfp_hours << @total_rfp_hours
        estimated_hours << @total_estimated_hours

        if ts.empty?
          labels << "-"
        else
          labels << ts.max_by{|t| t.spent_on}.spent_on.strftime("%m %d")
        end
    end
    time_entries_line.values = time_entries
    rfp_hours_line.values = rfp_hours
    estimated_hours_line.values = estimated_hours

    x_labels = XAxisLabels.new
    x_labels.labels = labels
    x = XAxis.new
    x.set_labels(x_labels)

    y = YAxis.new
    y_max = (total > @total_rfp_hours ? total : @total_rfp_hours) + 20
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

  def show
    @graph = open_flash_chart_object(900, 600, "/yojitsu/graph_code/#{params[:id]}")
    
    @category_time_entries = {}
    @sprints.each do |sprint|
      sprint.stories.each do |story|
        story.tasks.each do |task|
          category = task.category || IssueCategory.new(:name => "カテゴリなし")
          @category_time_entries[category.name] ||= 0
          @category_time_entries[category.name] += task.spent_hours
        end
      end
    end
  end

  private
  def setup
    @project = Project.find(params[:id])

    # Sprints
    # ※BacklogsプラグインのSprintは将来的にVersionと同一視されなくなるので注意
    @sprints = Sprint.find(:all, 
                           :order => 'sprint_start_date ASC, effective_date ASC',
                           :conditions => ["project_id = ?", @project.id])

    # rfp hours
    @total_rfp_hours = @project.custom_values[0] ? @project.custom_values[0].to_s.to_f : 0.0

    # estimated hours
    @total_estimated_hours = @sprints.inject(0.0) do |sum, sprint|
      next sum unless sprint.estimated_hours
      sum + sprint.estimated_hours
    end

    # spent hours
    @total_spent_hours = @sprints.inject(0.0) do |sum, sprint|
      next sum unless sprint.spent_hours
      sum + sprint.spent_hours
    end

    # add backlog hours to estimated and spent hours
    #@backlog = Story.product_backlog(@project)
    #@backlog.each do |task|
    #  if task.estimated_hours
    #    @total_estimated_hours += task.estimated_hours
    #  end
    #  if task.spent_hours
    #    @total_spent_hours += task.spent_hours
    #  end
    #end
  end
end