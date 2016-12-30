#!/bin/bash

function try() {
	"$@"
	code=$?
	if [ $code -ne 0 ]; then
		echo "$1 failed: exit status $code"
		exit 1
	fi
}

function fixReadme() {
	local content=$(cat $1)
	# Make images viewable outside GitHub
	content=$(echo "$content" | perl -p -e 's/github\.com\/(.*?)\/blob\/master\/images/raw\.githubusercontent\.com\/$1\/master\/images/g;')
	# Tell Hugo not to process shortcode samples
	content=$(echo "$content" | perl -0pe 's/{{%(.*?)%}}/{{%\/*$1*\/%}}/sg;')
	content=$(echo "$content" | perl -0pe 's/{{<(.*?)>}}/{{<\/*$1*\/>}}/sg;')

	echo "$content"
}

# Silent pushd
pushd() {
	command pushd "$@" >/dev/null
}

# Silent popd
popd() {
	command popd "$@" >/dev/null
}

# Load the repositories from the provided environment variables or our defaults
HUGO_THEME_SITE_REPO=${HUGO_THEME_SITE_REPO:-https://github.com/spf13/HugoThemesSite.git}
HUGO_BASIC_EXAMPLE_REPO=${HUGO_BASIC_EXAMPLE_REPO:-https://github.com/spf13/HugoBasicExample.git}
HUGO_THEMES_REPO=${HUGO_THEMES_REPO:-https://github.com/bep/hugoThemes.git}

echo "Using ${HUGO_THEMES_REPO} for themes"
echo "Using ${HUGO_THEME_SITE_REPO} for theme site"
echo "Using ${HUGO_BASIC_EXAMPLE_REPO} for example site"

GLOBIGNORE=.*
siteDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hugoThemeSite"

configTplPrefix="config-tpl"
configBase="${configTplPrefix}-base"
configBaseParams="${configTplPrefix}-params"

# This is the hugo Theme Site Builder
mkdir -p hugoThemeSite

pushd hugoThemeSite

if [ -d themeSite ]; then
	pushd themeSite
	git pull --rebase
	popd
else
	git clone ${HUGO_THEME_SITE_REPO} themeSite
fi

if [ -d exampleSite ]; then
	pushd exampleSite
	git pull --rebase
	popd
else
	git clone ${HUGO_BASIC_EXAMPLE_REPO} exampleSite
fi

pushd exampleSite

if [ -d themes ]; then
	pushd themes
	git fetch origin
	git reset --hard origin/master
	git submodule foreach git reset --hard
	git submodule update --init --recursive
	git clean -dff
	popd
else
	git clone --recursive ${HUGO_THEMES_REPO} themes
fi

popd

echo "BUILDING FROM" `pwd`

# Clean before new build
try rm -rf themeSite/public
try rm -rf themeSite/static/theme
try rm -rf themeSite/content
try rm -rf themeSite/static/images
try rm -rf exampleSite2

mkdir -p themeSite/content
mkdir -p themeSite/static/images

if [ $# -eq 1 ]; then
	BASEURL="$1"
else
	BASEURL="http://themes.gohugo.io"
fi

# persona: https://github.com/pcdummy/hugo-theme-persona/issues/1
# html5: https://github.com/simonmika/hugo-theme-html5/issues/2
# journal discontinued
# aurora: https://github.com/coryshaw/hugo-aurora-theme/issues/1
# hugo-plus: https://github.com/H4tch/hugo-plus/issues/5
# purehugo: purehugo:64: comment must be closed
blacklist=('persona', 'html5', 'journal', '.git', 'aurora', 'hugo-plus', 'purehugo')

# hugo-incorporated: too complicated, needs its own
#   exampleSite: https://github.com/nilproductions/hugo-incorporated/issues/24
# hugo-theme-arch: themes generates blank homepage
# hugo-smpl-theme: Promotional non-Hugo links
# hugo-theme-learn: the theme owner requested the disable of the theme demo, see https://github.com/spf13/hugoThemes/issues/172
# hugo-finite: Too big
noDemo=('hugo-incorporated', 'hugo-theme-arch', 'hugo-smpl-theme', 'hugo-theme-learn', 'hugo-finite')

errorCounter=0

for x in `ls -d exampleSite/themes/*/ | cut -d / -f3`; do
	blacklisted=`echo ${blacklist[*]} | grep "$x"`
	if [ "${blacklisted}" != "" ]; then
		continue
	fi

	generateDemo=true
	inNoDemo=`echo ${noDemo[*]} | grep "$x"`
	if [ "${inNoDemo}" != "" ]; then
		generateDemo=false
	fi

	echo " ==== PROCESSING " $x " ====== "

	cp exampleSite/themes/$x/images/screenshot.png themeSite/static/images/$x.screenshot.png
	cp exampleSite/themes/$x/images/tn.png themeSite/static/images/$x.tn.png

	echo "+++" >themeSite/content/$x.md
	echo "screenshot = \"/images/$x.screenshot.png\"" >>themeSite/content/$x.md
	echo "thumbnail = \"/images/$x.tn.png\"" >>themeSite/content/$x.md
	repo=`git -C exampleSite/themes/$x remote -v | head -n 1 | awk '{print$2}'`

	pushd exampleSite/themes
	themeCreated=`git log --reverse --pretty=format:"%ai" $x | head -1`
	pushd $x
	themeUpdated=`git log --pretty=format:"%ai" -n1`
	popd
	popd

	echo "date = \"$themeCreated\"" >>themeSite/content/$x.md
	echo "lastmod = \"$themeUpdated\"" >>themeSite/content/$x.md

	echo "source = \"$repo\"" >>themeSite/content/$x.md

	if $generateDemo; then
		if [ -d "exampleSite/themes/$x/exampleSite" ]; then
			# Use content and config in exampleSite
			echo "Building site for theme ${x} using its own exampleSite"

			# Hugo should exit with an error code on these ...
			if [ ! -d "exampleSite/themes/$x/exampleSite/content" ]; then
				echo "Example site for theme ${x} missing /content folder"
				generateDemo=false
			fi
			if [ ! -d "exampleSite/themes/$x/exampleSite/static" ]; then
				echo "Example site for theme ${x} missing /static folder"
				generateDemo=false
			fi

			ln -s ${siteDir}/exampleSite/themes/$x/exampleSite ${siteDir}/exampleSite2
			ln -s ${siteDir}/exampleSite/themes ${siteDir}/exampleSite2/themes
			env HUGO_THEMESDIR=${siteDir}/exampleSite/themes hugo -s exampleSite2 -d ../themeSite/static/theme/$x/ --canonifyURLs=true -t $x -b $BASEURL/theme/$x/
			if [ $? -ne 0 ]; then
				echo "FAILED to create exampleSite for $x"
				errorCounter=$((errorCounter + 1))
				generateDemo=false
			fi
			rm ${siteDir}/exampleSite2/themes
			rm ${siteDir}/exampleSite2

		else

			themeConfig="${TMPDIR}config-${x}.toml"
			baseConfig="${configBase}.toml"
			paramsConfig="${configBaseParams}.toml"

			if [ -f "themeSite/templates/${configBase}-${x}.toml" ]; then
				baseConfig="${configBase}-${x}.toml"
			fi

			if [ -f "themeSite/templates/${configBaseParams}-${x}.toml" ]; then
				paramsConfig="${configBaseParams}-${x}.toml"
			fi

			cat themeSite/templates/${baseConfig} >${themeConfig}
			cat themeSite/templates/${paramsConfig} >>${themeConfig}

			echo "Building site for theme ${x} using config ${themeConfig}"
			hugo -s exampleSite --config=${themeConfig} --canonifyURLs=true -d ../themeSite/static/theme/$x/ -t $x -b $BASEURL/theme/$x/
			if [ $? -ne 0 ]; then
				echo "FAILED to create demo site for $x"
				errorCounter=$((errorCounter + 1))
				generateDemo=false
			fi
		fi
	fi

	if $generateDemo; then
		echo "demo = \"/theme/$x/\"" >>themeSite/content/$x.md
	fi

	cat exampleSite/themes/$x/theme.toml >>themeSite/content/$x.md
	echo -en "\n+++\n\n" >>themeSite/content/$x.md

	fixReadme exampleSite/themes/$x/README.md >>themeSite/content/$x.md

	if ((errorCounter > 50)); then
		echo "FAILED: Too many ($errorCounter) errors!"
		exit 1
	fi

done

unset GLOBIGNORE

echo -en "Finished with $errorCounter errors ...\n"

echo -en "**********************************************************************\n"
echo -en "\n"
echo -en "to view the site locally run 'hugo server -s hugoThemeSite/themeSite'\n"
echo -en "\n"
echo -en "**********************************************************************\n"
