# Can't use alpine since it can't run 32-bit binaries, and the SDK doesn't have
# 64-bit binaries
FROM ubuntu:20.04

RUN apt-get update

# Install Android SDK
## Dependencies
RUN apt-get install -y unzip curl ca-certificates \
  openjdk-8-jdk
ENV JAVA8_HOME /usr/lib/jvm/java-8-openjdk-amd64
ENV JAVA_HOME $JAVA8_HOME
## SDK tools
ENV ANDROID_SDK_ROOT /opt/android-sdk-linux
ARG ANDROID_COMPILE_SDK=29
ARG ANDROID_BUILD_TOOLS=29.0.3

ARG VERSION_SDK_TOOLS=6200805
ENV ANDROID_SDK_ZIP http://dl.google.com/android/repository/commandlinetools-linux-${VERSION_SDK_TOOLS}_latest.zip

##Node version
ARG NODE_VERSION=10.x

RUN mkdir -p ${ANDROID_SDK_ROOT}/cmdline-tools \
  && curl -L $ANDROID_SDK_ZIP --output sdk.zip \
  && unzip sdk.zip -d ${ANDROID_SDK_ROOT}/cmdline-tools\
  && rm sdk.zip

#ENV PATH $PATH:$ANDROID_HOME/tools:$ANDROID_HOME/tools/bin:$ANDROID_HOME/platform-tools
ENV PATH $PATH:$ANDROID_SDK_ROOT/emulator:$ANDROID_SDK_ROOT/tools:$ANDROID_SDK_ROOT/cmdline-tools/tools/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH

## SDK
### sdkmanager will throw up warnings if this file does not exist
### TODO find out what this is needed for
RUN mkdir -p /root/.android && touch /root/.android/repositories.cfg
### Use verbose flags to keep an eye on progress - some commands take a very long
### time, and without the verbose flag it's impossible to tell if it's hung or
### still working
RUN yes | sdkmanager --update
RUN yes | sdkmanager --sdk_root=${ANDROID_SDK_ROOT} "tools"
RUN yes | sdkmanager --verbose 'platform-tools'
RUN yes | sdkmanager --verbose 'tools'
RUN yes | sdkmanager --verbose 'emulator'
RUN yes | sdkmanager --verbose 'extras;android;m2repository'
RUN yes | sdkmanager --verbose 'extras;google;google_play_services'
RUN yes | sdkmanager --verbose 'extras;google;m2repository'
RUN yes | sdkmanager --verbose "build-tools;$ANDROID_BUILD_TOOLS"
RUN yes | sdkmanager --verbose "platforms;android-$ANDROID_COMPILE_SDK"
RUN yes | sdkmanager --verbose "system-images;android-$ANDROID_COMPILE_SDK;default;x86_64"

RUN yes | sdkmanager --update --verbose
RUN yes | sdkmanager --licenses
# Done installing Android SDK




# Set up React Native
## Install node, yarn, and react-native-cli
# RUN apt-get install -y nodejs npm \
#   && npm install -g yarn \
#   && yarn global add react-native-cli

### This is the port that the React Native app will use to communicate with the
### build server for loading new builds, and also where the debugger page will
### be hosted (ie. localhost:8081/debugger-ui)
EXPOSE 8081
## Install watchman - required for React Native to build native code, and for
## hot code reloading
# RUN apt-get install -y git \
# RUN apt update -qq && apt install -qq -y --no-install-recommends \
#   libssl-dev autoconf automake \
#   libtool python-dev \
#   pkg-config

RUN apt update -qq && apt install -qq -y --no-install-recommends \
  apt-transport-https \
  curl \
  file \
  gcc \
  git \
  g++ \
  gnupg2 \
  libc++1-10 \
  libgl1 \
  libtcmalloc-minimal4 \
  make \
  openjdk-8-jdk-headless \
  openssh-client \
  python3 \
  python3-distutils \
  rsync \
  ruby \
  ruby-dev \
  tzdata \
  unzip \
  sudo \
  ninja-build \
  zip \
  libssl-dev autoconf automake \
  libtool \
  pkg-config \
  && gem install bundler \
  && rm -rf /var/lib/apt/lists/*;

# RUN git clone https://github.com/facebook/watchman.git -b v4.9.0 --depth 1 \
#   && cd watchman \
#   && ./autogen.sh \
#   && ./configure --without-python  --without-pcre --enable-lenient\
#   && make \
#   && sudo make install \
#   && cd .. \
#   && rm -rf watchman

RUN \
  git clone https://github.com/facebook/watchman.git &&\
  cd watchman &&\
  git checkout v4.9.0 &&\
  ./autogen.sh &&\
  ./configure --without-python  --without-pcre --enable-lenient &&\
  make &&\
  make install \
  && cd .. \
  && rm -rf watchman
# Done setting up react-native



# install nodejs and yarn packages from nodesource
RUN curl -sL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - \
  && apt-get update -qq \
  && apt-get install -qq -y --no-install-recommends nodejs \
  && npm i -g yarn \
  && rm -rf /var/lib/apt/lists/* \
  && yarn global add react-native-cli


# Install and set up Tini
# ARG TINI_VERSION=v0.18.0
# ADD https://github.com/krallin/tini/releases/download/${TINI_VERSION}/tini /tini
# RUN chmod +x /tini

# ENTRYPOINT ["/tini", "--"]
# Done installing Tini

##Configure to use 'rn' command
ENV PATH $PATH:$HOME/react-native-docker/bin:$PATH

# Set up non-root user
ARG USERNAME=dev
ARG UID=1000
RUN adduser --uid $UID --disabled-password --gecos '' $USERNAME
## Give the user ownership of the SDK installation directory (so it can run
## SDK commands)
RUN chown -R $USERNAME:$USERNAME $ANDROID_SDK_ROOT
# Allow the Docker user to play audio through the host's pulseaudio
ENV XDG_RUNTIME_DIR /run/user/$UID
RUN mkdir -p $XDG_RUNTIME_DIR && chown -R $USERNAME:$USERNAME $XDG_RUNTIME_DIR
## No need for root from here on out, so switch to the non-root user to avoid
## complication (eg. having to chown more files due to creating as root, etc.)
USER $USERNAME
## `emulator` has a bug where it won't work unless run from a specific
## directory, so set up a convenience function to run it from anywhere. Can't
## use eg. `.bashrc` because tini doesn't load it
ARG USER_BIN_DIR=/home/$USERNAME/.bin
RUN mkdir $USER_BIN_DIR \
  && echo '(cd "$ANDROID_SDK_ROOT"/tools && ./emulator "$@")' \
  >> $USER_BIN_DIR/emulator \
  && chmod +x $USER_BIN_DIR/emulator
ENV PATH $USER_BIN_DIR:$PATH
# Done setting up non-root user


ENV PROJECT_MOUNT=/project
WORKDIR $PROJECT_MOUNT

RUN mkdir -p .${PROJECT_MOUNT}/Iperum/App 
#Copy Volume to map

COPY ./home/felipealvarenga/dev/Iperum/App $PROJECT_MOUNT/Iperum/App 


# Tell gradle to store dependencies in a sub directory of the android project -
# this persists the dependencies between builds, speeding up build times. Make
# sure to add android/gradle_deps to the project's .gitignore
ENV GRADLE_USER_HOME $PROJECT_MOUNT/android/gradle_deps
