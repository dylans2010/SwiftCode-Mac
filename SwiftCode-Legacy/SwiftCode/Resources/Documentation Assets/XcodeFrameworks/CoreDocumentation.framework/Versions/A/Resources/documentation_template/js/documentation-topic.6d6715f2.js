/*!
 * This source file is part of the Swift.org open source project
 *
 * Copyright (c) 2021 Apple Inc. and the Swift project authors
 * Licensed under Apache License v2.0 with Runtime Library Exception
 *
 * See https://swift.org/LICENSE.txt for license information
 * See https://swift.org/CONTRIBUTORS.txt for Swift project authors
 */
"use strict";(self["webpackChunkkudu"]=self["webpackChunkkudu"]||[]).push([[545,633],{9056:function(e,a,t){t.r(a),t.d(a,{default:function(){return k}});var i=t(9905);const n={backgroundStyle:"background-style",hideOnThisPage:"hide-on-this-page",hideOverview:"hide-overview",showOnThisPage:"show-on-this-page"},u={plain:"plain"};var d,s,l={computed:{customMetadata:({topicData:e={}})=>{var a,t;return null!==(a=null===e||void 0===e||null===(t=e.metadata)||void 0===t?void 0:t.customMetadata)&&void 0!==a?a:{}},disableHeroBackground:({checkValue:e})=>e(n.backgroundStyle,u.plain),enableOnThisPageNav:({isEnabled:e})=>e(n.showOnThisPage)&&!e(n.hideOnThisPage),hideOverview:({isEnabled:e})=>e(n.hideOverview)},methods:{checkValue(e,a){return this.customMetadata[e]===a},isEnabled(e){return this.checkValue(e,"true")}}},o=t(8966),h={extends:i["default"],mixins:[l,o["default"]],computed:{enableQuickNavigation:()=>!0,rootLink:()=>({path:"/documentation/"})},watch:{hideOverview(e){this.store.state.hideOverview=e}}},r=h,c=t(2401),v=(0,c.A)(r,d,s,!1,null,null,null),k=v.exports}}]);