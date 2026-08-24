{if !empty($img_background)}
    {main_include 'profile_background.inc.tpl'}
{/if}

{if empty($error)}
    <section class="dc-profile-shell">
        <header class="dc-profile-hero">
            <div class="dc-profile-avatar-wrap">
                {{ UserDesignCoreModel::userStatus($id) }}
                {{ (new AvatarDesignCore)->lightBox($username, $first_name, $sex, 400) }}
            </div>
            <div class="dc-profile-hero-copy">
                <span class="dc-eyebrow">DeseoCerca · Perfil 18+</span>
                <h1>{username} <span class="dc-profile-age">{age}</span></h1>
                <p class="dc-profile-place">📍 {city}{if !empty($state)}, {state}{/if} · {country}</p>
                {if !empty($punchline)}<p class="dc-profile-punchline">{punchline}</p>{/if}

                {if $is_logged AND !$is_own_profile}
                    <div class="dc-profile-actions">
                        {if !$interaction_blocked}
                            <form method="post" action="{{ $design->url('user','favorite','toggle') }}" class="dc-inline-form">
                                <input type="hidden" name="security_token" value="{favorite_csrf}" />
                                <input type="hidden" name="favorite_id" value="{id}" />
                                <button type="submit" class="btn btn-default">{if $is_favorite}♥ Guardado{else}♡ Guardar{/if}</button>
                            </form>

                            {if $is_im_enabled}
                                <a rel="nofollow" href="{messenger_link}" class="btn btn-primary">Chat</a>
                            {/if}
                            {if $is_mail_enabled}
                                <a rel="nofollow" href="{mail_link}" class="btn btn-default">Mensaje</a>
                            {/if}
                            {if $is_friend_enabled}
                                <a rel="nofollow" href="{friend_link}" class="btn btn-default">
                                    {if $is_approved_friend}Quitar contacto{elseif $is_pending_friend}Gestionar contacto{else}Añadir contacto{/if}
                                </a>
                            {/if}
                            <span class="dc-report-action">{{ $design->report($id, $username, $first_name, $sex) }}</span>
                        {else}
                            <span class="dc-blocked-notice">Has bloqueado este perfil. Las interacciones están desactivadas.</span>
                        {/if}

                        <form method="post" action="{{ $design->url('user','block','toggle') }}" class="dc-inline-form">
                            <input type="hidden" name="security_token" value="{block_csrf}" />
                            <input type="hidden" name="blocked_id" value="{id}" />
                            <button type="submit" class="btn btn-default">{if $is_blocked_by_me}Desbloquear{else}Bloquear{/if}</button>
                        </form>
                    </div>
                {elseif $is_own_profile}
                    <div class="dc-profile-actions">
                        <a class="btn btn-default" href="{{ $design->url('user','favorite','index') }}">♡ Mis favoritos</a>
                        <a class="btn btn-default" href="{{ $design->url('user','history','index') }}">◷ Vistos recientemente</a>
                        <a class="btn btn-default" href="{{ $design->url('user','block','index') }}">🛡 Bloqueados</a>
                    </div>
                {/if}
            </div>
        </header>

        <ol id="toc">
            <li><a href="#general"><span>{lang 'Info'}</span></a></li>
            {if $is_map_enabled}<li><a href="#map"><span>{lang 'Map'}</span></a></li>{/if}
            {if $is_relatedprofile_enabled}<li><a href="#related_profile"><span>{lang 'Similar Profiles'}</span></a></li>{/if}
            {if $is_friend_enabled AND !$interaction_blocked}
                <li><a href="#friend"><span>{friend_link_name}</span></a></li>
                {if $is_logged AND !$is_own_profile}<li><a href="#mutual_friend"><span>{mutual_friend_link_name}</span></a></li>{/if}
            {/if}
            {if $is_picture_enabled}<li><a href="#picture"><span>{lang 'Photos'}</span></a></li>{/if}
            {if $is_video_enabled}<li><a href="#video"><span>{lang 'Videos'}</span></a></li>{/if}
            <li><a href="#visitor"><span>{lang 'Recently Viewed'}</span></a></li>
        </ol>

        <div class="content" id="general" itemscope="itemscope" itemtype="http://schema.org/Person">
            <div class="dc-profile-facts">
                <p><span class="bold">{lang 'I am a:'}</span> <span class="italic"><a itemprop="gender" href="{{ $design->url('user','browse','index', '?country='.$country_code.'&match_sex='.$sex) }}">{lang $sex}</a></span></p>

                {if !empty($match_sex)}
                    <p><span class="bold">{lang 'Looking for a:'}</span> <span class="italic"><a href="{{ $design->url('user','browse','index', '?country='.$country_code) }}{match_sex_search}">{lang $match_sex}</a></span></p>
                {/if}

                <p><span class="bold">{lang 'First name:'}</span> <span class="italic"><a itemprop="name" href="{{ $design->url('user','browse','index', '?country='.$country_code.'&first_name='.$first_name) }}">{first_name}</a></span></p>

                {if !empty($middle_name)}
                    <p><span class="bold">{lang 'Middle name:'}</span> <span class="italic">{middle_name}</span></p>
                {/if}

                {if !empty($last_name)}
                    <p><span class="bold">{lang 'Last name:'}</span> <span class="italic">{last_name}</span></p>
                {/if}

                {if !empty($age)}
                    <p><span class="bold">{lang 'Age:'}</span> <span class="italic"><a itemprop="birthDate" href="{{ $design->url('user','browse','index', '?country='.$country_code.'&age='.$birth_date) }}">{age}</a></span></p>
                {/if}

                {each $key => $val in $fields}
                    {if $key != 'description' AND $key != 'middleName' AND $key != 'punchline' AND !empty($val)}
                        {{ $val = escape($val, true) }}
                        {if stripos($key, 'height') !== false}
                            <p><span class="bold">{lang 'Height:'}</span> <span class="italic">{{ (new Framework\Math\Measure\Height($val))->display(true) }}</span></p>
                        {elseif stripos($key, 'weight') !== false}
                            <p><span class="bold">{lang 'Weight:'}</span> <span class="italic">{{ (new Framework\Math\Measure\Weight($val))->display(true) }}</span></p>
                        {elseif $key == 'country'}
                            <p><span class="bold">{lang 'Country:'}</span> <span class="italic"><a itemprop="nationality" href="{{ $design->url('user','browse','index', '?country='.$country_code) }}">{country}</a></span></p>
                        {elseif $key == 'city'}
                            <p><span class="bold">{lang 'City/Town:'}</span> <span class="italic"><a itemprop="homeLocation" href="{{ $design->url('user','browse','index', '?country='.$country_code.'&city='.$city) }}">{city}</a></span></p>
                        {elseif $key == 'state'}
                            <p><span class="bold">{lang 'State/Province:'}</span> <span class="italic"><a href="{{ $design->url('user','browse','index', '?country='.$country_code.'&state='.$state) }}">{state}</a></span></p>
                        {elseif $key == 'zipCode'}
                            {* Postal code is intentionally not rendered on DeseoCerca profile pages. *}
                        {elseif stripos($key, 'website') !== false}
                            <p>{{ $design->favicon($val) }} <span class="bold">{lang 'Site/Blog:'}</span> <span itemprop="url" class="italic">{{ $design->urlTag($val) }}</span></p>
                        {elseif stripos($key, 'socialNetworkSite') !== false}
                            <p>{{ $design->favicon($val) }} <span class="bold">{lang 'Social Profile:'}</span> <span itemprop="url" class="italic">{{ $design->urlTag($val) }}</span></p>
                        {/if}
                    {/if}
                {/each}

                {if !empty($join_date)}<p><span class="bold">{lang 'Join Date:'}</span> <span class="italic">{join_date}</span></p>{/if}
                {if !empty($last_activity)}<p><span class="bold">{lang 'Last Activity:'}</span> <span class="italic">{last_activity}</span></p>{/if}
                <p><span class="bold">{lang 'Views:'}</span> <span class="italic">{% Framework\Mvc\Model\Statistic::getView($id,DbTableName::MEMBER) %}</span></p>
            </div>

            {{ RatingDesignCore::voting($id,DbTableName::MEMBER) }}

            <div class="profile_desc">
                {if !empty($description)}<div itemprop="description" class="quote italic">{description}</div>{/if}
            </div>
        </div>

        {if $is_map_enabled}
            <div class="content" id="map">
                <p class="dc-map-privacy-note">Ubicación aproximada por ciudad. DeseoCerca no muestra tu dirección exacta.</p>
                {map}
            </div>
        {/if}

        {if $is_relatedprofile_enabled}
            <div class="content" id="related_profile">
                <script>
                    var url_related_profile_block = '{{ $design->url('related-profile','main','index',$id) }}';
                    $('#related_profile').load(url_related_profile_block + ' #related_profile_block');
                </script>
            </div>
        {/if}

        {if $is_friend_enabled AND !$interaction_blocked}
            <div class="content" id="friend">
                <script>
                    var url_friend_block = '{{ $design->url('friend','main','index',$username) }}';
                    $('#friend').load(url_friend_block + ' #friend_block');
                </script>
            </div>
        {/if}

        {if $is_friend_enabled AND $is_logged AND !$is_own_profile AND !$interaction_blocked}
            <div class="content" id="mutual_friend">
                <script>
                    var url_mutual_friend_block = '{{ $design->url('friend','main','mutual',$username) }}';
                    $('#mutual_friend').load(url_mutual_friend_block + ' #friend_block');
                </script>
            </div>
        {/if}

        {if $is_picture_enabled}
            <div class="content" id="picture">
                <script>
                    var url_picture_block = '{{ $design->url('picture','main','albums',$username.'?show_add_album_btn='.((int)$is_own_profile)) }}';
                    $('#picture').load(url_picture_block + ' #picture_block');
                </script>
            </div>
        {/if}

        {if $is_video_enabled}
            <div class="content" id="video">
                <script>
                    var url_video_block = '{{ $design->url('video','main','albums',$username.'?show_add_album_btn='.((int)$is_own_profile)) }}';
                    $('#video').load(url_video_block + ' #video_block');
                </script>
            </div>
        {/if}

        <div class="content" id="visitor">
            <script>
                var url_visitor_block = '{{ $design->url('user','visitor','index',$username) }}';
                $('#visitor').load(url_visitor_block + ' #visitor_block');
            </script>
        </div>

        <div class="clear"></div>
        <p class="center dc-profile-secondary-actions">
            {{ $design->like($username, $first_name, $sex) }}
            {if !$is_own_profile} · {{ $design->report($id, $username, $first_name, $sex) }}{/if}
        </p>
        {{ $design->socialMediaWidgets() }}
        {{ CommentDesignCore::link($id, 'profile') }}

        <script src="{url_static_js}tabs.js"></script>
        <script>
            tabs('p', [
                'general',
                {if $is_map_enabled}'map',{/if}
                {if $is_relatedprofile_enabled}'related_profile',{/if}
                {if $is_friend_enabled AND !$interaction_blocked}
                    'friend',
                    {if $is_logged AND !$is_own_profile}'mutual_friend',{/if}
                {/if}
                {if $is_picture_enabled}'picture',{/if}
                {if $is_video_enabled}'video',{/if}
                'visitor'
            ]);
        </script>

        <script>
            $('ol#toc li a[href=#map]').click(function() { location.reload(); });
        </script>

        {if !$is_logged AND !AdminCore::auth()}
            {{ $design->staticFiles('js', PH7_LAYOUT . PH7_SYS . PH7_MOD . $registry->module . PH7_SH . PH7_TPL . PH7_TPL_MOD_NAME . PH7_SH . PH7_JS, 'signup_popup.js') }}
        {/if}
    </section>
{else}
    <p class="center">{error}</p>
{/if}
