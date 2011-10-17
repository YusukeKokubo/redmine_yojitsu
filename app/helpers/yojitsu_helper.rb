module YojitsuHelper
  def l_hour(hour)
    return "-" unless hour
    sprintf("%.1f", hour)
  end

  def rowspan_sprint(sprint)
    sprint.stories.count + 1
  end

  def rowspan_story(story)
    story.children.count + 1
  end

  def rowspan_backlog(backlog)
    backlog.size + 1
  end

  def class_overcost(issue)
    return "overcost-normal" unless issue.initial_estimate and issue.spent_hours
    return "overcost-normal" if issue.initial_estimate >= issue.spent_hours
    return "overcost-attension" if issue.spent_hours / issue.initial_estimate <= 1.2
    "overcost-caution"
  end
end
