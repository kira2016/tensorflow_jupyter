# Copyright (c) Jupyter Development Team.
# Distributed under the terms of the Modified BSD License.

ARG ROOT_CONTAINER=tensorflow/tensorflow:1.15.4

ARG BASE_CONTAINER=$ROOT_CONTAINER
FROM $BASE_CONTAINER

LABEL maintainer="Jupyter Project <jupyter@googlegroups.com>"
ARG NB_USER="jovyan"
ARG NB_UID="1000"
ARG NB_GID="100"

# Fix DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER root

# Install all OS dependencies for notebook server that starts but lacks all
# features (e.g., download as all possible file formats)
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update \
 && apt-get install -yq --no-install-recommends \
    wget \
    bzip2 \
    ca-certificates \
    sudo \
    locales \
    fonts-liberation \
    run-one \
    apt-utils \
    python-tables \
 && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen

# Configure environment
ENV  SHELL=/bin/bash \
    NB_USER=$NB_USER \
    NB_UID=$NB_UID \
    NB_GID=$NB_GID \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8
ENV HOME=/home/$NB_USER

# Copy a script that we will use to correct permissions after running certain commands
COPY fix-permissions /usr/local/bin/fix-permissions
RUN chmod a+rx /usr/local/bin/fix-permissions

# Enable prompt color in the skeleton .bashrc before creating the default NB_USER
# hadolint ignore=SC2016
RUN sed -i 's/^#force_color_prompt=yes/force_color_prompt=yes/' /etc/skel/.bashrc && \
   # Add call to conda init script see https://stackoverflow.com/a/58081608/4413446
   #echo 'eval "$(command conda shell.bash hook 2> /dev/null)"' >> /etc/skel/.bashrc 

# Create NB_USER with name jovyan user with UID=1000 and in the 'users' group
# and make sure these dirs are writable by the `users` group.
RUN echo "auth requisite pam_deny.so" >> /etc/pam.d/su && \
    sed -i.bak -e 's/^%admin/#%admin/' /etc/sudoers && \
    sed -i.bak -e 's/^%sudo/#%sudo/' /etc/sudoers && \
    useradd -m -s /bin/bash -N -u $NB_UID $NB_USER && \
    chmod g+w /etc/passwd && \
    fix-permissions $HOME 

# Setup work directory for backward-compatibility
RUN mkdir /home/$NB_USER/work && \
    fix-permissions /home/$NB_USER

# Install Tini
ENV TINI_VERSION v0.18.0
#ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /usr/local/bin/tini
COPY tini /usr/local/bin/tini
RUN chmod +x /usr/local/bin/tini

#installl nodejs
ADD node-v12.19.0-linux-x64/ /usr/local/ 
RUN fix-permissions /usr/local/

RUN /usr/bin/python3 -m pip install --upgrade pip

RUN pip install 'notebook==6.1.4' \
    'jupyterhub==1.1.0' \
    'jupyterlab==2.2.8' && \
    npm cache clean --force && \
    jupyter notebook --generate-config && \
    fix-permissions /home/$NB_USER

# Install all OS dependencies for fully functional notebook server
#COPY sources.list /etc/apt/sources.list
RUN apt-get update --fix-missing && apt-get install -yq --no-install-recommends \
    build-essential \
    emacs-nox \
    vim-tiny \
    git \
    inkscape \
    jed \
    libsm6 \
    libxext-dev \
    libxrender1 \
    lmodern \
    netcat \
    python-dev \
    # ---- nbconvert dependencies ----
    texlive-xetex \
    texlive-fonts-recommended \
    texlive-plain-generic \
    # ----
    tzdata \
    unzip \
    nano-tiny \
    ffmpeg \
    dvipng \
    cm-super \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create alternative for nano -> nano-tiny
RUN update-alternatives --install /usr/bin/nano nano /bin/nano-tiny 10

# Install Python 3 packages
RUN pip install -i https://mirrors.aliyun.com/pypi/simple/ \
    'beautifulsoup4==4.9.*' \
    'bokeh==2.2.*' \
    'bottleneck==1.3.*' \
    'cloudpickle==1.6.*' \
    'cython==0.29.*' \
    'dask==2.25.*' \
    'dill==0.3.*' \
    'h5py==2.10.*' \
    'ipywidgets==7.5.*' \
    'ipympl==0.5.*'\
    'matplotlib==3.3.*' \
    'numba==0.51.*' \
    'numexpr==2.7.*' \
    'pandas==1.1.*' \
    'patsy==0.5.*' \
    'protobuf==3.12.*' \
    'scikit-image==0.17.*' \
    'scikit-learn==0.23.*' \
    'scipy==1.5.*' \
    'seaborn==0.11.*' \
    'sqlalchemy==1.3.*' \
    'statsmodels==0.12.*' \
    'sympy==1.6.*' \
    'vincent==0.4.*' \
    'widgetsnbextension==3.5.*'\
    'xlrd==1.2.*' 

    # Activate ipywidgets extension in the environment that runs the notebook server
 RUN jupyter nbextension enable --py widgetsnbextension --sys-prefix && \
    # Also activate ipywidgets extension for JupyterLab
    # Check this URL for most recent compatibilities
    # https://github.com/jupyter-widgets/ipywidgets/tree/master/packages/jupyterlab-manager

    jupyter labextension install @jupyter-widgets/jupyterlab-manager@^2.0.0 --no-build && \
    jupyter labextension install @bokeh/jupyter_bokeh@^2.0.0 --no-build && \
    jupyter labextension install jupyter-matplotlib@^0.7.2 --no-build && \
    jupyter lab build -y && \
    jupyter lab clean -y && \
    rm -rf "/home/${NB_USER}/.cache/yarn" && \
    rm -rf "/home/${NB_USER}/.node-gyp" && \
    fix-permissions "/home/${NB_USER}"

# Install facets which does not have a pip or conda package at the moment
 ADD facets /tmp/facets/
 RUN ls /tmp/
 RUN jupyter nbextension install /tmp/facets/facets-dist/ --sys-prefix && \
    rm -rf /tmp/facets && \
    fix-permissions "/home/${NB_USER}"

# Import matplotlib the first time to build the font cache.
ENV XDG_CACHE_HOME="/home/${NB_USER}/.cache/"

RUN MPLBACKEND=Agg python -c "import matplotlib.pyplot" && \
    fix-permissions "/home/${NB_USER}"

EXPOSE 8888
# Configure container startup
ENTRYPOINT ["tini", "-g", "--"]
CMD ["start-notebook.sh"]

# Copy local files as late as possible to avoid cache busting
COPY start.sh start-notebook.sh start-singleuser.sh /usr/local/bin/
COPY jupyter_notebook_config.py /etc/jupyter/

COPY bash.bashrc /etc/bash.bashrc
RUN fix-permissions /etc/jupyter/ \
    && fix-permissions /usr/local/bin/*.sh
RUN fix-permissions /etc/jupyter/

USER $NB_UID
WORKDIR $HOME
    
