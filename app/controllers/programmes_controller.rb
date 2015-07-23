class ProgrammesController < ApplicationController
  include Seek::IndexPager
  include Seek::DestroyHandling

  before_filter :programmes_enabled?
  before_filter :login_required,:except=>[:show,:index]
  before_filter :find_and_authorize_requested_item,:only=>[:edit,:update,:destroy]
  before_filter :find_requested_item, :only=>[:show,:admin, :initiate_spawn_project,:spawn_project]
  before_filter :find_assets, :only=>[:index]
  before_filter :is_user_admin_auth,:only=>[:initiate_spawn_project,:spawn_project]


  skip_before_filter :project_membership_required

  include Seek::BreadCrumbs

  respond_to :html

  def create
    @programme = Programme.new(params[:programme])

    flash[:notice] = "The #{t('programme').capitalize} was successfully created." if @programme.save

    #current person becomes the administrator
    User.current_user.person.is_programme_administrator=true,@programme
    disable_authorization_checks{User.current_user.person.save!}

    respond_with(@programme)
  end

  def update

    flash[:notice] = "The #{t('programme').capitalize} was successfully updated." if @programme.update_attributes(params[:programme])
    respond_with(@programme)
  end

  def edit
    respond_with(@programme)
  end

  def new
    @programme=Programme.new
    respond_with(@programme)
  end

  def show
    respond_with(@programme)
  end

  def initiate_spawn_project
    @available_projects = Project.where('programme_id != ? OR programme_id IS NULL',@programme.id)
    respond_with(@programme,@available_projects)
  end

  def spawn_project
    proj_params=params[:project]
    @ancestor_project = Project.find(proj_params[:ancestor_id])
    @project = @ancestor_project.spawn({:title=>proj_params[:title],:description=>proj_params[:description],:web_page=>proj_params[:web_page],:programme=>@programme})
    if @project.save
      flash[:notice]="The #{t('project')} '#{@ancestor_project.title}' was successfully spawned for the '#{t('programme')}' #{@programme.title}"
      redirect_to project_path(@project)
    else
      @available_projects = Project.where('programme_id != ? OR programme_id IS NULL',@programme.id)
      render :action=>:initiate_spawn_project
    end
  end

end
