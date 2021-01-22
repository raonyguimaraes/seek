class WorkflowsController < ApplicationController
  include Seek::IndexPager
  include Seek::AssetsCommon

  before_action :workflows_enabled?
  before_action :find_assets, only: [:index]
  before_action :find_and_authorize_requested_item, except: [:index, :new, :create, :preview, :update_annotations_ajax]
  before_action :find_display_asset, only: [:show, :download, :diagram, :ro_crate]
  before_action :login_required, only: [:create, :create_version, :new_version,
                                        :create_from_files, :create_from_ro_crate,
                                        :create_metadata, :provide_metadata]
  before_action :find_or_initialize_workflow, only: [:create_from_files, :create_from_ro_crate]

  include Seek::Publishing::PublishingCommon
  include Seek::Doi::Minting
  include Seek::IsaGraphExtensions
  include RoCrateHandling

  api_actions :index, :show, :create, :update, :destroy

  rescue_from WorkflowDiagram::UnsupportedFormat do
    head :not_acceptable
  end

  def new_version
    respond_to do |format|
      format.html
    end
  end

  def create_version
    if handle_upload_data(true)
      comments = params[:revision_comments]
      respond_to do |format|
        if @workflow.save_as_new_version(comments)

          flash[:notice]="New version uploaded - now on version #{@workflow.version}"
        else
          flash[:error]="Unable to save new version"
        end
        format.html {redirect_to @workflow }
      end
    else
      flash[:error] = flash.now[:error]
      redirect_to @workflow
    end
  end

  # PUT /Workflows/1
  def update
    update_annotations(params[:tag_list], @workflow) if params.key?(:tag_list)
    update_sharing_policies @workflow
    update_relationships(@workflow,params)

    respond_to do |format|
      if @workflow.update_attributes(workflow_params)
        flash[:notice] = "#{t('workflow')} metadata was successfully updated."
        format.html { redirect_to workflow_path(@workflow) }
        format.json { render json: @workflow, include: [params[:include]] }
      else
        format.html { render action: 'edit' }
        format.json { render json: json_api_errors(@workflow), status: :unprocessable_entity }
      end
    end
  end

  # Takes a single RO-Crate zip file
  def create_from_ro_crate
    respond_to do |format|
      if handle_upload_data(@workflow.persisted?) && @workflow.content_blob.save && extract_metadata
        format.html { render :provide_metadata }
      else
        format.html { render action: :new, status: :unprocessable_entity }
      end
    end
  end

  # Creates an RO-Crate zip file from several files
  def create_from_files
    @workflow = Workflow.new(workflow_class_id: params[:workflow_class_id])
    @crate_builder = WorkflowCrateBuilder.new(ro_crate_params)
    @crate_builder.workflow_class = @workflow.workflow_class
    blob_params = @crate_builder.build
    @workflow.build_content_blob(blob_params)

    respond_to do |format|
      if blob_params && @workflow.content_blob.save && extract_metadata
        format.html { render :provide_metadata }
      else
        format.html { render action: :new, status: :unprocessable_entity }
      end
    end
  end

  # Takes a remote Git repository and target ref
  def create_from_git
    @workflow = Workflow.new(git_version_attributes: { git_repository_id: params[:git_repository_id], ref: params[:ref] })
    @metadata = {}
    @warnings ||= @metadata.delete(:warnings) || []
    @errors ||= @metadata.delete(:errors) || []
    respond_to do |format|
      format.html { render :provide_metadata }
    end
  end

  def extract_metadata
    begin
      extractor = @workflow.extractor
      retrieve_content @workflow.content_blob # Hack
      @metadata = extractor.metadata
      @warnings ||= @metadata.delete(:warnings) || []
      @errors ||= @metadata.delete(:errors) || []
      @workflow.assign_attributes(@metadata)
    rescue StandardError => e
      raise e unless Rails.env.production?
      Seek::Errors::ExceptionForwarder.send_notification(e, data: {
        message: "Problem attempting to extract metadata for content blob #{params[:content_blob_id]}" })
      flash[:error] = 'An unexpected error occurred whilst extracting workflow metadata.'
      return false
    end

    true
  end
  #
  # # Displays the form Wizard for providing the metadata for the workflow
  # def provide_metadata
  #   extract_metadata
  #   metadata = @metadata
  #   @warnings ||= metadata.delete(:warnings) || []
  #   @errors ||= metadata.delete(:errors) || []
  #   @workflow.assign_attributes(metadata)
  #
  #   respond_to do |format|
  #     format.html
  #   end
  # end

  # Receives the submitted metadata and registers the workflow
  def create_metadata
    @workflow = Workflow.new(workflow_params)
    update_sharing_policies(@workflow)
    filter_associated_projects(@workflow)

    blob = ContentBlob.find_by_uuid(params[:content_blob_uuid])
    @workflow.errors.add(:content_blob, 'was not found') unless blob
    @workflow.content_blob = blob
    update_annotations(params[:tag_list], @workflow) if params.key?(:tag_list)
    if params[:content_blob_uuid].present?
      valid = blob && @workflow.save && blob.save
    elsif @workflow.git_version_attributes.present?
      valid = @workflow.save
    else
      valid = false
    end

    if valid
      update_relationships(@workflow, params)

      respond_to do |format|
        flash[:notice] = "#{t('workflow')} was successfully uploaded and saved." if flash.now[:notice].nil?

        format.html { redirect_to workflow_path(@workflow) }
        format.json { render json: @workflow }
      end
    else
      respond_to do |format|
        format.html do
          render :provide_metadata, status: :unprocessable_entity
        end
      end
    end
  end

  def create_version_metadata
    @workflow = Workflow.find(params[:id])
    @workflow.assign_attributes(workflow_params)
    update_sharing_policies(@workflow)
    filter_associated_projects(@workflow)

    #associate the content blob with the workflow
    blob = ContentBlob.find_by_uuid(params[:content_blob_uuid])
    @workflow.errors.add(:content_blob, 'was not found') unless blob
    new_version = @workflow.version += 1
    old_content_blob = @workflow.content_blob
    blob.asset_version = new_version
    @workflow.content_blob = blob
    # asset_id on the previous content blob gets blanked out after the above command is run, so need to do:
    old_content_blob.update_column(:asset_id, @workflow.id) if old_content_blob
    update_annotations(params[:tag_list], @workflow) if params.key?(:tag_list)

    if blob && @workflow.save_as_new_version(params[:revision_comments]) && blob.save
      update_relationships(@workflow, params)

      respond_to do |format|
        flash[:notice] = "#{t('workflow')} was successfully uploaded and saved." if flash.now[:notice].nil?

        format.html { redirect_to workflow_path(@workflow) }
        format.json { render json: @workflow }
      end
    else
      respond_to do |format|
        format.html do
          render :provide_metadata, status: :unprocessable_entity
        end
      end
    end
  end

  def diagram
    diagram_format = params.key?(:diagram_format) ? params[:diagram_format] : @workflow.default_diagram_format
    @diagram = @display_workflow.diagram(diagram_format)
    response.set_header('Content-Security-Policy', "default-src 'self'")
    respond_to do |format|
      format.html do
        if @diagram
          send_file(@diagram.path,
                    filename: @diagram.filename,
                    type: @diagram.content_type,
                    disposition: 'inline')
        else
          head :not_found
        end
      end
    end
  end

  def download
    ro_crate
  end

  def ro_crate
    send_ro_crate(@display_workflow.ro_crate_zip,
                  "workflow-#{@workflow.id}-#{@display_workflow.version}.crate.zip")
  end

  private

  def find_or_initialize_workflow
    if params[:workflow_id]
      @workflow = Workflow.find(params[:workflow_id])
    else
      @workflow = Workflow.new(workflow_class_id: params[:workflow_class_id])
    end
  end

  def retrieve_content(blob)
    unless blob.file_exists?
      blob.remote_content_fetch_task&.cancel
      blob.retrieve
    end
  end

  def workflow_params
    params.require(:workflow).permit(:title, :description, :workflow_class_id, # :metadata,
                                     { project_ids: [] }, :license, :other_creators,
                                     { special_auth_codes_attributes: [:code, :expiration_date, :id, :_destroy] },
                                     { creator_ids: [] }, { assay_assets_attributes: [:assay_id] }, { scales: [] },
                                     { publication_ids: [] }, :internals, :maturity_level, :source_link_url,
                                     discussion_links_attributes:[:id, :url, :label, :_destroy])
  end

  alias_method :asset_params, :workflow_params

  def ro_crate_params
    params.require(:ro_crate).permit({ workflow: [:data, :data_url, :make_local_copy] },
                                     { abstract_cwl: [:data, :data_url, :make_local_copy] },
                                     { diagram: [:data, :data_url, :make_local_copy] })
  end
end
