trigger SRV_CaseTrigger on Case (before insert, before Update, after insert, after update) {
    try{   
        Boolean srv_time;
        //Retrieve custom settings
        ServiceSettings__c objSettings = ServiceSettings__c.getInstance();
        boolean blnDisable = objSettings.Disable_Automations__c; //This is the custom setting to disable service side automations
        string strRecTypeIds = objSettings.Record_Type_Ids__c; //Custom setting that stores the service record typeids.
        
        if (blnDisable == false) //Proceed to this logic only if Disable Automations setting is not checked.
        {
            if(trigger.isbefore && Trigger.isUpdate)
            {
                if (SRV_CaseHandler.isTriggerExecuted)
                {
                    system.debug('before update ' + SRV_CaseHandler.isTriggerExecuted);
                    SRV_CaseHandler.SendCaseNotification(trigger.new, trigger.oldMap);
                    SRV_CaseHandler.isTriggerExecuted = false;
                    system.debug('after sendCase ' + SRV_CaseHandler.isTriggerExecuted);
                }
                ///Create Recurring Cases 
                SRV_CaseHandler.CreateRecurringCases(trigger.new,trigger.oldmap);
                SRV_CaseHandler.capture_Timezone_Service_Event(trigger.new);
                
            }
            
            if (trigger.isBefore && trigger.isInsert)
            {
                SRV_CaseHandler.DefaultCaseValues(trigger.new);
            }
            
            if (trigger.isAfter && trigger.isInsert)
            {
                system.debug('after Insert ' + SRV_CaseHandler.isTriggerExecuted);
                SRV_CaseHandler.DeleteDuplicateCases(trigger.new);
                SRV_CaseHandler.SendCaseNotification(trigger.new, null);
                SRV_CaseHandler.isTriggerExecuted = false;
                system.debug('after send Insert ' + SRV_CaseHandler.isTriggerExecuted);
            }
        }
    }
    catch(Exception Ex)
    {
        trigger.New[0].addError(Ex);
    }
}